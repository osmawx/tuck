import AppKit

/// Owns the three status items (dot + two dividers) and opens hidden icon menus.
///
/// Layout left to right: [always hidden icons] [alwaysHiddenDivider] [hidden icons] [hiddenDivider] [dot] [shown icons].
/// A divider with a huge length pushes every icon to its left off the screen, so both stay collapsed:
/// the panel requests a temporary reveal to capture or open a hidden icon.
@MainActor
final class StatusBarController: NSObject {
    /// Time for the menu bar to lay icons out again after a divider changes length.
    private static let RELAYOUT_DELAY_NANOSECONDS: UInt64 = 250_000_000
    private static let DOT_DIAMETER: CGFloat = 7

    private let toggleItem: NSStatusItem
    private let hiddenDivider: NSStatusItem
    private let alwaysHiddenDivider: NSStatusItem
    private(set) var isPresentingNativeMenu = false
    private(set) var layoutRevision = 0
    private var menuGeneration = 0
    private var isCapturingHiddenItems = false
    private(set) var menuFailureMessage: String?

    /// Left click on the dot.
    var onToggleHiddenBar: (() -> Void)?
    /// "Menu Bar Layout…" in the dot's menu.
    var onOpenLayout: (() -> Void)?
    /// Starts an interactive check in builds with the updater.
    var onCheckForUpdates: (() -> Void)?

    /// Restores the saved positions before registering the three status items.
    override init() {
        SavedBarLayout.restoreCompactPositions()
        // Creation order matters on first launch: later items are placed further left.
        toggleItem = Self.makeItem(name: OwnItemName.toggle)
        hiddenDivider = Self.makeItem(name: OwnItemName.hiddenDivider)
        alwaysHiddenDivider = Self.makeItem(name: OwnItemName.alwaysHiddenDivider)
        super.init()

        if let button = toggleItem.button {
            button.image = Self.dotImage()
            button.target = self
            button.action = #selector(handleToggleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Hidden menu bar items")
        }
        setRevealed(false)
    }

    // MARK: Geometry

    /// Screen frame of the dot, used to place the hidden items panel under it.
    var toggleFrame: CGRect? { toggleItem.button?.window?.frame }

    /// Current widths of our items, as the sorter needs them.
    func ownWidths() -> OwnItemWidths {
        OwnItemWidths(
            toggle: toggleItem.button?.window?.frame.width ?? 0,
            hiddenDivider: hiddenDivider.button?.window?.frame.width ?? COLLAPSED_DIVIDER_LENGTH,
            alwaysHiddenDivider: alwaysHiddenDivider.button?.window?.frame.width ?? COLLAPSED_DIVIDER_LENGTH
        )
    }

    /// X positions of both dividers' windows, used to sort icons into sections.
    func dividerFrames() -> (hidden: CGRect, alwaysHidden: CGRect)? {
        guard let hiddenFrame = hiddenDivider.button?.window?.frame,
              let alwaysHiddenFrame = alwaysHiddenDivider.button?.window?.frame else { return nil }
        return (hiddenFrame, alwaysHiddenFrame)
    }

    /// Briefly reveals both hidden sections so their real status item pictures can be cached.
    func captureHiddenItemImages(shouldContinue: @escaping () -> Bool) async {
        guard !isPresentingNativeMenu, shouldContinue() else { return }
        let generation = menuGeneration
        isCapturingHiddenItems = true
        setRevealed(true, includingAlwaysHidden: true)
        defer {
            isCapturingHiddenItems = false
            if generation == menuGeneration { setRevealed(false) }
        }
        // Legacy snapshots may be empty even with permission. Keep windows revealed for the async retry.
        try? await Task.sleep(nanoseconds: Self.RELAYOUT_DELAY_NANOSECONDS * 2)
        guard shouldContinue(), !Task.isCancelled, generation == menuGeneration else { return }
        let isCurrent = {
            shouldContinue() && !Task.isCancelled && !self.isPresentingNativeMenu && self.menuGeneration == generation
        }
        let items = await MenuBarScanner.scan(shouldContinue: isCurrent)
        await MenuBarScanner.captureMissingImages(from: items, shouldContinue: isCurrent)
    }

    // MARK: Opening hidden icons

    /// Reveals the hidden section and leaves the source app in charge of its original menu.
    func openMenu(for item: MenuBarItem) async -> Bool {
        guard !isPresentingNativeMenu else { return true }
        isPresentingNativeMenu = true
        menuFailureMessage = nil
        menuGeneration += 1
        let generation = menuGeneration
        setRevealed(true)
        defer {
            if generation == menuGeneration {
                setRevealed(false)
                isPresentingNativeMenu = false
            }
        }
        try? await Task.sleep(nanoseconds: Self.RELAYOUT_DELAY_NANOSECONDS)
        guard generation == menuGeneration else { return true }

        // Do not press a stale/off-screen AX element merely because a delay has elapsed.
        let currentItem = await waitForVisibleItem(item, generation: generation)
        guard generation == menuGeneration, !Task.isCancelled else { return true }
        guard let currentItem else {
            menuFailureMessage = "Иконка не появилась в трее. Откройте Menu Bar Layout и нажмите Sort My Bar для исправления сохранённых позиций."
            return false
        }
        let existingWindows = Self.menuWindowIDs(for: item.processIdentifier)
        AXUIElementSetMessagingTimeout(currentItem.element, 0.5)
        let result = AXUIElementPerformAction(currentItem.element, kAXPressAction as CFString)
        MenuDiagnostics.record("original menu press \(item.id): \(result.rawValue)")
        if result != .success && result != .cannotComplete {
            let showResult = AXUIElementPerformAction(currentItem.element, kAXShowMenuAction as CFString)
            if showResult != .success && showResult != .cannotComplete { return false }
        }

        let deadline = Date().addingTimeInterval(2)
        var hasSeenMenu = false
        var absentChecks = 0
        while generation == menuGeneration && !Task.isCancelled {
            let visibleWindows = Self.menuWindowIDs(for: item.processIdentifier).subtracting(existingWindows)
            if !visibleWindows.isEmpty {
                hasSeenMenu = true
                absentChecks = 0
            } else if hasSeenMenu {
                // Allow a short gap when AppKit replaces a menu window or opens a submenu.
                absentChecks += 1
                if absentChecks >= 3 {
                    MenuDiagnostics.record("original menu closed: \(item.id)")
                    return true
                }
            } else if Date() >= deadline {
                MenuDiagnostics.record("original menu not visible: \(item.id)")
                return false
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return true
    }

    /// Waits for relayout to expose the status item, allowing vertical window padding.
    private func waitForVisibleItem(_ target: MenuBarItem, generation: Int) async -> MenuBarItem? {
        let deadline = Date().addingTimeInterval(2)
        let displays = MenuBarImageCapture.displayBounds()
        while generation == menuGeneration && Date() < deadline && !Task.isCancelled {
            let items = await MenuBarScanner.scan(captureImages: false, processIdentifier: target.processIdentifier)
            guard generation == menuGeneration, !Task.isCancelled else { return nil }
            if let item = items.first(where: { $0.id == target.id }) {
                if MenuBarGeometry.visibleBounds(of: item.frame, on: displays) != nil {
                    MenuDiagnostics.record("revealed icon \(target.id): \(item.frame)")
                    return item
                }
                MenuDiagnostics.record("waiting for icon \(target.id): \(item.frame)")
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        MenuDiagnostics.record("icon reveal timed out: \(target.id)")
        return nil
    }

    /// Restores the collapsed section when the hidden bar is explicitly closed.
    func dismissMenu() {
        menuGeneration += 1
        if isPresentingNativeMenu || isCapturingHiddenItems { setRevealed(false) }
        isPresentingNativeMenu = false
    }

    /// Tracks the source app's windows and native popup menus, excluding status items and our panel.
    private static func menuWindowIDs(for processIdentifier: pid_t) -> Set<CGWindowID> {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return Set(windows.compactMap { window in
            guard let owner = window[kCGWindowOwnerPID as String] as? Int,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  let identifier = window[kCGWindowNumber as String] as? UInt32,
                  owner != Int(ProcessInfo.processInfo.processIdentifier), layer != 25,
                  owner == Int(processIdentifier) || layer == 101 else { return nil }
            return identifier
        })
    }

    // MARK: Private

    /// Creates a status item; the autosave name keeps its position across launches.
    private static func makeItem(name: String) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = name
        return item
    }

    /// Small filled circle drawn as a template image so it follows the menu bar color.
    private static func dotImage() -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let dotRect = NSRect(
                x: rect.midX - DOT_DIAMETER / 2, y: rect.midY - DOT_DIAMETER / 2,
                width: DOT_DIAMETER, height: DOT_DIAMETER
            )
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Reveals the requested section while its icon is being captured or opened.
    private func setRevealed(_ isRevealed: Bool, includingAlwaysHidden: Bool = false) {
        let hiddenLength = isRevealed ? EXPANDED_DIVIDER_LENGTH : COLLAPSED_DIVIDER_LENGTH
        let alwaysHiddenLength = isRevealed && includingAlwaysHidden
            ? EXPANDED_DIVIDER_LENGTH : COLLAPSED_DIVIDER_LENGTH
        guard hiddenDivider.length != hiddenLength || alwaysHiddenDivider.length != alwaysHiddenLength else { return }
        layoutRevision += 1
        hiddenDivider.length = hiddenLength
        alwaysHiddenDivider.length = alwaysHiddenLength
    }

    /// Left click opens the hidden items panel; right click or ctrl-click opens the menu.
    @objc private func handleToggleClick() {
        let event = NSApp.currentEvent
        let isMenuClick = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if isMenuClick {
            showMenu()
        } else {
            onToggleHiddenBar?()
        }
    }

    /// Shows the context menu under the dot.
    private func showMenu() {
        let menu = NSMenu()
        let layoutEntry = NSMenuItem(title: "Menu Bar Layout…", action: #selector(openLayout), keyEquivalent: ",")
        layoutEntry.target = self
        menu.addItem(layoutEntry)
        if onCheckForUpdates != nil {
            let updateEntry = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
            updateEntry.target = self
            menu.addItem(updateEntry)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Tuck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // Attach temporarily so a plain click still opens the panel.
        toggleItem.menu = menu
        toggleItem.button?.performClick(nil)
        toggleItem.menu = nil
    }

    /// Forwards the update action to the app's updater.
    @objc private func checkForUpdates() {
        onCheckForUpdates?()
    }

    /// Opens the layout window from the dot’s context menu.
    @objc private func openLayout() {
        onOpenLayout?()
    }
}
