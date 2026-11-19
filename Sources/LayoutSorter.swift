import AppKit

/// Desired menu bar order, left to right, per section.
struct BarArrangement {
    var alwaysHidden: [MenuBarItem]
    var hidden: [MenuBarItem]
    var shown: [MenuBarItem]
}

/// Current widths of our own status items, needed to compute positions past them.
struct OwnItemWidths {
    let toggle: CGFloat
    let hiddenDivider: CGFloat
    let alwaysHiddenDivider: CGFloat
}

/// Re-orders the menu bar without touching the mouse.
///
/// Every app stores where its icon sits as "NSStatusItem Preferred Position <name>" in its own
/// preferences (distance from the right screen edge). When Control Center restarts, every app
/// re-registers its icons at those stored positions. So: write the positions we want, restart
/// Control Center, and the menu bar comes back in the new order.
enum LayoutSorter {
    private static let POSITION_KEY_PREFIX = "NSStatusItem Preferred Position "
    /// Gap kept between our first position and the fixed system items on the right.
    private static let FIXED_ITEMS_MARGIN: CGFloat = 8
    /// Padding AppKit adds around each item's content.
    private static let ITEM_PADDING: CGFloat = 8

    /// One position to write.
    struct PositionWrite {
        let domain: String
        let key: String
        let value: Double
    }

    /// Writes positions for `arrangement` and restarts Control Center.
    /// Returns display names of items whose position could not be written.
    @MainActor
    static func apply(_ arrangement: BarArrangement, fixedItems: [MenuBarItem], ownWidths: OwnItemWidths) async -> [String] {
        let screenWidth = NSScreen.screens.first?.frame.width ?? 0
        let (positions, failedNames) = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let writes = positionWrites(for: arrangement, fixedItems: fixedItems, ownWidths: ownWidths,
                                            screenWidth: screenWidth)
                let failedNames = writes.external.filter { !writePosition($0.write) }.map(\.name)
                let positions = Dictionary(uniqueKeysWithValues: writes.own.map { ($0.key, $0.value) })
                continuation.resume(returning: (positions, failedNames))
            }
        }
        SavedBarLayout.saveCompactPositions(positions)

        await restartControlCenter()
        return failedNames
    }

    // MARK: Positions

    /// Computes values right to left: every item gets a larger distance from the right edge than its right neighbour.
    /// Internal (not private) so the result can be checked without writing anything.
    static func positionWrites(
        for arrangement: BarArrangement,
        fixedItems: [MenuBarItem],
        ownWidths: OwnItemWidths,
        screenWidth: CGFloat = NSScreen.screens.first?.frame.width ?? 0
    ) -> (external: [(write: PositionWrite, name: String)], own: [PositionWrite]) {
        enum Slot {
            case item(MenuBarItem)
            case own(name: String, width: CGFloat)
        }

        // Persist compact positions. Collapsed divider widths are a temporary hiding mechanism,
        // not part of the logical layout; persisting them strands app icons off screen.
        let leftToRight: [Slot] =
            arrangement.alwaysHidden.map(Slot.item)
            + [.own(name: OwnItemName.alwaysHiddenDivider, width: EXPANDED_DIVIDER_LENGTH)]
            + arrangement.hidden.map(Slot.item)
            + [.own(name: OwnItemName.hiddenDivider, width: EXPANDED_DIVIDER_LENGTH),
               .own(name: OwnItemName.toggle, width: ownWidths.toggle)]
            + arrangement.shown.map(Slot.item)

        // Off-screen fixed items must not shift the compact positions outside the display.
        let visibleFixedItems = fixedItems.filter { $0.frame.minX >= 0 && $0.frame.maxX <= screenWidth }
        let leftmostFixedX = visibleFixedItems.map(\.frame.minX).min() ?? screenWidth
        var distance = Double(screenWidth - leftmostFixedX + FIXED_ITEMS_MARGIN)

        let keys = positionKeys(for: leftToRight.compactMap { if case .item(let item) = $0 { return item } else { return nil } })
        var external: [(write: PositionWrite, name: String)] = []
        var own: [PositionWrite] = []

        for slot in leftToRight.reversed() {
            switch slot {
            case .item(let item):
                distance += Double(item.frame.width + ITEM_PADDING)
                guard let key = keys[item.id] else { continue }
                external.append((PositionWrite(domain: item.bundleIdentifier, key: key, value: distance), item.displayName))
            case .own(let name, let width):
                distance += Double(width)
                own.append(PositionWrite(domain: OWN_BUNDLE_ID, key: POSITION_KEY_PREFIX + name, value: distance))
            }
        }
        return (external, own)
    }

    /// Finds the preference key of every item. Keys of one app sorted by value (largest = leftmost)
    /// line up with that app's items sorted left to right.
    private static func positionKeys(for items: [MenuBarItem]) -> [String: String] {
        var result: [String: String] = [:]
        for (bundleIdentifier, appItems) in Dictionary(grouping: items, by: \.bundleIdentifier) {
            let stored = storedPositions(domain: bundleIdentifier)
            let ordered = appItems.sorted { $0.indexInApp < $1.indexInApp }
            let fallbackNames = keyNames(stored: stored, itemCount: ordered.count)
            var usedNames = Set<String>()
            let namedItems = Dictionary(grouping: ordered.compactMap { item in
                item.autosaveName.map { (name: $0, item: item) }
            }, by: \.name)
            for (name, matches) in namedItems where matches.count == 1 {
                result[matches[0].item.id] = POSITION_KEY_PREFIX + name
                usedNames.insert(name)
            }
            for (item, fallbackName) in zip(ordered, fallbackNames) where result[item.id] == nil {
                let name = usedNames.contains(fallbackName)
                    ? fallbackNames.first { !usedNames.contains($0) } : fallbackName
                if let name {
                    result[item.id] = POSITION_KEY_PREFIX + name
                    usedNames.insert(name)
                }
            }
        }
        return result
    }

    /// Autosave names for `itemCount` items, left to right.
    private static func keyNames(stored: [String: Double], itemCount: Int) -> [String] {
        // AppKit's default names are Item-0, Item-1...; apps may also use their own names.
        if stored.count == itemCount {
            return stored.sorted { $0.value > $1.value }.map(\.key)
        }
        let defaultNames = (0..<itemCount).map { "Item-\($0)" }
        if itemCount == 1, stored.count > 1, stored["Item-0"] == nil {
            // Several custom names but one visible icon: the leftmost stored one is the best guess.
            return [stored.max { $0.value < $1.value }!.key]
        }
        return defaultNames
    }

    /// "NSStatusItem Preferred Position" values stored by an app, keyed by autosave name.
    private static func storedPositions(domain: String) -> [String: Double] {
        // `defaults` also resolves sandboxed apps' container preferences.
        guard let output = run("/usr/bin/defaults", ["export", domain, "-"]),
              let plist = try? PropertyListSerialization.propertyList(from: output, format: nil) as? [String: Any] else { return [:] }
        var result: [String: Double] = [:]
        for (key, value) in plist where key.hasPrefix(POSITION_KEY_PREFIX) {
            if let number = value as? NSNumber {
                result[String(key.dropFirst(POSITION_KEY_PREFIX.count))] = number.doubleValue
            }
        }
        return result
    }

    // MARK: Processes

    /// Writes one position through `defaults` so the running app sees it via cfprefsd.
    private static func writePosition(_ write: PositionWrite) -> Bool {
        run("/usr/bin/defaults", ["write", write.domain, write.key, "-float", String(write.value)]) != nil
    }

    /// Restarts Control Center (launchd starts it again) and waits for icons to come back.
    private static func restartControlCenter() async {
        _ = run("/usr/bin/killall", ["ControlCenter"])
        try? await Task.sleep(nanoseconds: 2_500_000_000)
    }

    /// Runs a tool and returns its standard output, or nil when it fails.
    @discardableResult
    private static func run(_ path: String, _ arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            NSLog("Tuck: failed to run %@: %@", path, error.localizedDescription)
            return nil
        }
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            NSLog("Tuck: %@ %@ exited with %d", path, arguments.joined(separator: " "), process.terminationStatus)
            return nil
        }
        return output
    }
}
