import AppKit

/// One icon in the menu bar.
struct MenuBarItem: Identifiable {
    /// Stable id: bundle id plus index of the item among that app's items (left to right).
    let id: String
    let bundleIdentifier: String
    let processIdentifier: pid_t
    let displayName: String
    /// Index among the same app's items, left to right.
    let indexInApp: Int
    /// Frame in top-left screen coordinates (same space as CGEvent and CGWindowList).
    let frame: CGRect
    /// Accessibility element; `AXPress` on it opens the item's menu without touching the mouse.
    let element: AXUIElement
    /// Window that draws the item (owned by Control Center on macOS 26); used for screenshots.
    let windowID: CGWindowID?
    /// Picture of the item as it looks in the menu bar, or nil without Screen Recording access.
    let image: NSImage?
    /// System items (clock, Control Center, Wi-Fi...) stay where macOS puts them.
    let isMovable: Bool
    /// WindowServer registration name, when available.
    var autosaveName: String? = nil

    /// Identifies an icon across changes in its position and process ID.
    var layoutID: String {
        if let autosaveName { return "\(bundleIdentifier)#name:\(autosaveName)" }
        return id
    }

    /// Replaces the picture without changing the geometry sampled by the scanner.
    func withImage(_ image: NSImage?) -> MenuBarItem {
        MenuBarItem(id: id, bundleIdentifier: bundleIdentifier, processIdentifier: processIdentifier,
                    displayName: displayName, indexInApp: indexInApp, frame: frame, element: element,
                    windowID: windowID, image: image, isMovable: isMovable, autosaveName: autosaveName)
    }
}

/// Finds menu bar icons through the Accessibility API and matches them with their windows.
enum MenuBarScanner {
    /// Window layer of status items (kCGStatusWindowLevel).
    private static let STATUS_WINDOW_LAYER = 25
    /// Wider entries are dividers, not icons (the clock, the widest real item, is ~150 pt).
    private static let MAX_ICON_WIDTH: CGFloat = 400
    private static let SCAN_QUEUE = DispatchQueue(label: "com.local.hider.menu-bar-scan", qos: .userInitiated)

    /// App metadata sampled before the worker starts querying Accessibility.
    private struct Application {
        let processIdentifier: pid_t
        let bundleIdentifier: String
        let name: String
    }

    /// Last real menu bar picture for each item, including items now hidden off screen.
    @MainActor private static var capturedImages: [String: NSImage] = [:]
    @MainActor private static var modernImageIDs = Set<String>()
    @MainActor private static var captureResumesAt = Date.distantPast

    /// Keeps transient Space animation surfaces out of the icon cache.
    @MainActor
    static func suspendImageCapture() {
        captureResumesAt = Date().addingTimeInterval(1.5)
    }

    /// Samples geometry and legacy pictures on the serial worker, then merges pictures on the main actor.
    @MainActor
    static func scan(captureImages: Bool = true, processIdentifier: pid_t? = nil,
                     shouldContinue: () -> Bool = { true }) async -> [MenuBarItem] {
        let captureStartedAt = Date()
        let shouldCapture = captureImages && captureStartedAt >= captureResumesAt &&
            MenuBarImageCapture.isScreenRecordingGranted
        let skippedIDs = modernImageIDs
        let displays = shouldCapture ? MenuBarImageCapture.displayBounds() : []
        let scale = shouldCapture ? NSScreen.main?.backingScaleFactor ?? 2 : 1
        let applications = runningApplications(processIdentifier: processIdentifier)
        let items = await withCheckedContinuation { continuation in
            SCAN_QUEUE.async {
                continuation.resume(returning: collectItems(from: applications, captureImages: shouldCapture,
                    skippedIDs: skippedIDs, displays: displays, scale: scale))
            }
        }
        guard shouldContinue() else { return [] }
        // A live frame or a Space change may arrive while the legacy scan is in flight.
        if shouldCapture && captureStartedAt >= captureResumesAt {
            for item in items where !modernImageIDs.contains(item.id) {
                if let image = item.image { capturedImages[item.id] = image }
            }
        }
        return items.map { $0.withImage(capturedImages[$0.id]) }
    }

    /// Updates pictures from the cache without sampling Accessibility again.
    @MainActor
    static func applyingCachedImages(to items: [MenuBarItem]) -> [MenuBarItem] {
        items.map { $0.withImage(capturedImages[$0.id] ?? $0.image) }
    }

    /// Collects app metadata without moving AppKit objects onto the scan queue.
    @MainActor
    private static func runningApplications(processIdentifier: pid_t?) -> [Application] {
        let running = processIdentifier.map { identifier in
            NSRunningApplication(processIdentifier: identifier).map { [$0] } ?? []
        } ?? NSWorkspace.shared.runningApplications
        return running.compactMap { app in
            let bundleIdentifier = app.bundleIdentifier ?? "pid\(app.processIdentifier)"
            guard bundleIdentifier != OWN_BUNDLE_ID else { return nil }
            return Application(processIdentifier: app.processIdentifier, bundleIdentifier: bundleIdentifier,
                               name: app.localizedName ?? bundleIdentifier)
        }
    }

    /// Builds one geometry snapshot for the requested applications on the scan queue.
    private static func collectItems(from applications: [Application], captureImages: Bool, skippedIDs: Set<String>,
                                     displays: [CGRect], scale: CGFloat) -> [MenuBarItem] {
        let windows = statusWindows()
        var items: [MenuBarItem] = []

        for app in applications {
            let bundleIdentifier = app.bundleIdentifier
            let elements = extrasMenuBarItems(processIdentifier: app.processIdentifier)
            let appName = app.name
            for (index, entry) in elements.enumerated() {
                let itemID = "\(bundleIdentifier)#\(index)"
                let window = matchingWindow(for: entry.frame, in: windows)
                // Control Center can also report Tuck's own dot through Accessibility.
                if window?.isOwnItem == true { continue }
                let windowID = window?.id
                let capturedImage = captureImages && !skippedIDs.contains(itemID)
                    ? (windowID.flatMap { MenuBarImageCapture.image(of: $0, scale: scale) } ??
                        MenuBarImageCapture.image(in: entry.frame, displays: displays))
                    : nil
                items.append(MenuBarItem(
                    id: itemID,
                    bundleIdentifier: bundleIdentifier,
                    processIdentifier: app.processIdentifier,
                    // Apps with several icons get a number suffix to tell them apart.
                    displayName: entry.title ?? (index == 0 ? appName : "\(appName) \(index + 1)"),
                    indexInApp: index,
                    frame: entry.frame,
                    element: entry.element,
                    windowID: windowID,
                    image: capturedImage,
                    isMovable: bundleIdentifier != CONTROL_CENTER_BUNDLE_ID,
                    autosaveName: window?.name
                ))
            }
        }
        return items.sorted { $0.frame.minX < $1.frame.minX }
    }

    /// Refreshes pictures from one shared snapshot and validates any new stills together.
    @MainActor
    static func captureMissingImages(from items: [MenuBarItem], itemIDs: Set<String>? = nil,
                                     shouldContinue: () -> Bool) async {
        let batchStartedAt = Date()
        guard shouldContinue(), batchStartedAt >= captureResumesAt,
              MenuBarImageCapture.isScreenRecordingGranted else { return }
        let pending = captureCandidates(from: items, refreshExisting: true, itemIDs: itemIDs).filter {
            $0.image == nil || !MenuBarLiveCapture.isRunning(itemID: $0.id, windowID: $0.windowID)
        }
        guard !pending.isEmpty else { return }
        let windows = await MenuBarModernCapture.windows()
        let windowsByID = Dictionary(windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        var stills: [(item: MenuBarItem, image: NSImage)] = []
        for item in pending {
            guard shouldContinue(), batchStartedAt >= captureResumesAt else { return }
            let window = item.windowID.flatMap { windowsByID[$0] }
            if let window {
                let started = await MenuBarLiveCapture.start(item: item, window: window) { image in
                    guard Date() >= captureResumesAt else { return }
                    capturedImages[item.id] = image
                    modernImageIDs.insert(item.id)
                }
                guard shouldContinue(), batchStartedAt >= captureResumesAt else { return }
                // A stream can start before delivering its first usable frame.
                if started && capturedImages[item.id] != nil { continue }
            }
            if let image = await MenuBarModernCapture.image(for: item, window: window, shouldContinue: shouldContinue) {
                stills.append((item, image))
            }
        }

        guard !stills.isEmpty, shouldContinue(), batchStartedAt >= captureResumesAt else { return }
        let latest = await scan(captureImages: false, shouldContinue: shouldContinue)
        guard shouldContinue(), batchStartedAt >= captureResumesAt else { return }
        let latestByID = Dictionary(latest.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for still in stills {
            guard let currentItem = latestByID[still.item.id],
                  currentItem.processIdentifier == still.item.processIdentifier,
                  currentItem.windowID == still.item.windowID, currentItem.frame == still.item.frame,
                  capturedImages[still.item.id] === still.item.image else { continue }
            capturedImages[still.item.id] = still.image
            modernImageIDs.insert(still.item.id)
        }
    }

    /// Includes cached items for live refresh while limiting capture to the displayed section.
    static func captureCandidates(from items: [MenuBarItem], refreshExisting: Bool, itemIDs: Set<String>?) -> [MenuBarItem] {
        items.filter { (refreshExisting || $0.image == nil) && (itemIDs?.contains($0.id) ?? true) }
    }

    // MARK: Accessibility

    /// One status item as seen through Accessibility.
    private struct AXEntry {
        let element: AXUIElement
        let frame: CGRect
        let title: String?
    }

    /// Status items of one app, sorted left to right. Empty when the app has none.
    private static func extrasMenuBarItems(processIdentifier: pid_t) -> [AXEntry] {
        let application = AXUIElementCreateApplication(processIdentifier)
        guard let extrasBar: AXUIElement = attribute(of: application, "AXExtrasMenuBar"),
              let children: [AXUIElement] = attribute(of: extrasBar, kAXChildrenAttribute) else { return [] }

        return children
            .compactMap { element in
                frame(of: element).map { AXEntry(element: element, frame: $0, title: attribute(of: element, kAXDescriptionAttribute)) }
            }
            // Zero-size entries are items the system keeps out of the menu bar; very wide ones are
            // collapsed dividers (ours, reported by Control Center on macOS 26), not icons.
            .filter { $0.frame.width > 0 && $0.frame.height > 0 && $0.frame.width < MAX_ICON_WIDTH }
            .sorted { $0.frame.minX < $1.frame.minX }
    }

    /// Reads one attribute and casts it, nil when missing or of another type.
    private static func attribute<Value>(of element: AXUIElement, _ name: String) -> Value? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? Value
    }

    /// Reads position and size attributes of an accessibility element.
    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        // Safe casts: type ids were checked above.
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    // MARK: Windows

    /// WindowServer identity and geometry of a status item.
    private struct StatusWindow {
        let id: CGWindowID
        let frame: CGRect
        let isOwnItem: Bool
        let name: String?
    }

    /// Status item windows and their frames.
    private static func statusWindows() -> [StatusWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard info[kCGWindowLayer as String] as? Int == STATUS_WINDOW_LAYER,
                  let number = info[kCGWindowNumber as String] as? Int,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary) else { return nil }
            let name = info[kCGWindowName as String] as? String
            let isOwnItem = name == OwnItemName.toggle || name == OwnItemName.hiddenDivider ||
                name == OwnItemName.alwaysHiddenDivider
            return StatusWindow(id: CGWindowID(number), frame: bounds, isOwnItem: isOwnItem, name: name)
        }
    }

    /// Window whose bounds contain the centre of an item (window frames include a few points of padding).
    private static func matchingWindow(for frame: CGRect, in windows: [StatusWindow]) -> StatusWindow? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return windows
            .filter { $0.frame.width < MAX_ICON_WIDTH && $0.frame.contains(center) }
            // Prefer the tightest fit; our wide dividers can also contain the point.
            .min { $0.frame.width < $1.frame.width }
    }
}
