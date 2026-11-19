import AppKit
import Combine

/// State behind the layout window and the hidden items panel.
///
/// Dragging in the window only changes `sections` (instant, no mouse involved);
/// "Sort My Bar" writes the new order to the real menu bar.
@MainActor
final class BarModel: ObservableObject {
    private static let POLL_INTERVAL: TimeInterval = 1.5

    /// Movable icons per section, left to right, as the user arranged them.
    @Published private(set) var sections: [BarSection: [MenuBarItem]] = [:]
    /// System icons (clock, Control Center...) that always stay at the right end.
    @Published private(set) var fixedItems: [MenuBarItem] = []
    @Published private(set) var hasPendingChanges = false
    @Published private(set) var isSorting = false
    @Published private(set) var isAccessibilityGranted = AXIsProcessTrusted()
    @Published private(set) var isScreenRecordingGranted = MenuBarImageCapture.isScreenRecordingGranted
    /// Shown after a sort when some apps refused the new position.
    @Published private(set) var sortWarning: String?

    private let controller: StatusBarController
    private var pollTimer: Timer?
    private var pollingClients = Set<String>()
    private var attemptedImageCaptures: [String: Int] = [:]
    private var nextImageCaptureDate = Date.distantPast
    private var nextLiveImageCaptureDate = Date.distantPast
    private var needsLiveCaptureBootstrap = true
    private var isCapturingImages = false
    private var isScanning = false
    private var scanRevision = 0
    private var savedLayout = SavedBarLayout.load()
    private var checkedSavedProcesses: [String: pid_t] = [:]
    private var spaceChangeSubscription: AnyCancellable?
    private var appLaunchSubscription: AnyCancellable?
    private var scanResumesAt = Date.distantPast

    /// Observes desktop changes so animation frames cannot replace the current layout.
    init(controller: StatusBarController) {
        self.controller = controller
        spaceChangeSubscription = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scanRevision += 1
                    self?.scanResumesAt = Date().addingTimeInterval(1.5)
                    MenuBarScanner.suspendImageCapture()
                }
            }
        appLaunchSubscription = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.savedLayout != nil, self.pollingClients.isEmpty else { return }
                self.refresh()
            }
        refresh()
    }

    // MARK: Polling

    /// Starts or stops the periodic rescan for one client (window or panel); runs while any client needs it.
    func setPolling(_ isEnabled: Bool, client: String) {
        if isEnabled {
            if pollingClients.isEmpty { needsLiveCaptureBootstrap = true }
            pollingClients.insert(client)
        } else {
            pollingClients.remove(client)
        }
        if pollingClients.isEmpty { MenuBarLiveCapture.stopAll() }
        pollTimer?.invalidate()
        pollTimer = nil
        guard !pollingClients.isEmpty else { return }
        refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.POLL_INTERVAL, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: Permissions

    /// Shows the system Accessibility prompt.
    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Shows the system Screen Recording prompt (needed for real icon pictures).
    func requestScreenRecording() {
        MenuBarImageCapture.requestScreenRecording()
    }

    // MARK: Scanning

    /// Rescans the menu bar. While the user has unsorted changes, keeps their arrangement and only refreshes pictures.
    func refresh() {
        isAccessibilityGranted = AXIsProcessTrusted()
        isScreenRecordingGranted = MenuBarImageCapture.isScreenRecordingGranted
        guard Date() >= scanResumesAt, !isSorting, !isCapturingImages, !isScanning else { return }
        isScanning = true
        Task { await scanAndPublish() }
    }

    /// Discards an in-flight scan if the dividers, Space, or saved layout change.
    private func scanAndPublish() async {
        defer { isScanning = false }
        let revision = scanRevision
        let layoutRevision = controller.layoutRevision
        // Revealing an original menu changes geometry, but must not freeze its proxy picture.
        let isNativeMenuOpen = controller.isPresentingNativeMenu
        let isCurrent = {
            self.scanRevision == revision && self.controller.layoutRevision == layoutRevision && !self.isSorting
        }
        let items = await MenuBarScanner.scan(captureImages: !isNativeMenuOpen, shouldContinue: isCurrent)
        guard isCurrent() else { return }
        if isNativeMenuOpen {
            publishCachedImages()
            startLiveImageRefresh(items: items)
            return
        }

        fixedItems = items.filter { !$0.isMovable }
        let movable = items.filter(\.isMovable)
        let actualSections = Dictionary(grouping: movable, by: section(for:))
        if !hasPendingChanges, let restored = layoutToRestore(from: actualSections) {
            sections = restored
            applyLayout(restored)
            return
        }

        if isScreenRecordingGranted && !pollingClients.isEmpty && Date() >= nextImageCaptureDate {
            let uncapturedIDs = movable.filter { $0.image == nil && attemptedImageCaptures[$0.id, default: 0] < 3 }.map(\.id)
            if !uncapturedIDs.isEmpty || (needsLiveCaptureBootstrap && !pollingClients.isEmpty) {
                needsLiveCaptureBootstrap = false
                for identifier in uncapturedIDs { attemptedImageCaptures[identifier, default: 0] += 1 }
                nextImageCaptureDate = Date().addingTimeInterval(5)
                isCapturingImages = true
                Task {
                    await controller.captureHiddenItemImages {
                        !self.pollingClients.isEmpty && !self.isSorting && Date() >= self.scanResumesAt
                    }
                    isCapturingImages = false
                    publishCachedImages()
                }
            }
        } else if !isScreenRecordingGranted {
            attemptedImageCaptures.removeAll()
        }

        if hasPendingChanges {
            sections = merged(arrangement: sections, with: movable)
        } else {
            sections = actualSections
        }

        startLiveImageRefresh(items: items)
    }

    /// Captures current values even while a source app's original menu is tracking.
    private func startLiveImageRefresh(items: [MenuBarItem]) {
        guard !isCapturingImages, !pollingClients.isEmpty, isScreenRecordingGranted,
              Date() >= nextLiveImageCaptureDate else { return }
        let displayedItems = pollingClients.contains("window") ? items : (sections[.hidden] ?? [])
        let displayedIDs = Set(displayedItems.map(\.id))
        guard !displayedIDs.isEmpty else { return }
        nextLiveImageCaptureDate = Date().addingTimeInterval(Self.POLL_INTERVAL)
        isCapturingImages = true
        let revision = scanRevision
        let layoutRevision = controller.layoutRevision
        Task {
            await MenuBarScanner.captureMissingImages(from: items, itemIDs: displayedIDs) {
                !self.pollingClients.isEmpty && !self.isSorting && self.scanRevision == revision &&
                    self.controller.layoutRevision == layoutRevision
            }
            isCapturingImages = false
            nextLiveImageCaptureDate = max(nextLiveImageCaptureDate, Date().addingTimeInterval(0.25))
            publishCachedImages()
        }
    }

    /// Updates snapshots in place without rescanning or moving tiles between sections.
    private func publishCachedImages() {
        sections = sections.mapValues { MenuBarScanner.applyingCachedImages(to: $0) }
        fixedItems = MenuBarScanner.applyingCachedImages(to: fixedItems)
    }

    /// Discards unsorted changes and shows the real menu bar again.
    func revertChanges() {
        hasPendingChanges = false
        sortWarning = nil
        refresh()
    }

    // MARK: Arranging

    /// Moves an icon in the window only: to `section`, before the item at `index` (or at the end).
    func place(itemID: String, in section: BarSection, at index: Int) {
        guard !isSorting, let item = sections.values.joined().first(where: { $0.id == itemID }) else { return }

        var updated = sections.mapValues { $0.filter { $0.id != itemID } }
        var target = updated[section] ?? []
        target.insert(item, at: min(max(index, 0), target.count))
        updated[section] = target

        guard updated.mapValues({ $0.map(\.id) }) != sections.mapValues({ $0.map(\.id) }) else { return }
        sections = updated
        hasPendingChanges = true
        sortWarning = nil
    }

    /// Commits the arranged sections and applies them to the real menu bar.
    func sortMyBar() {
        guard !isSorting else { return }
        let layout = SavedBarLayout(sections: sections, previous: savedLayout)
        layout.save()
        savedLayout = layout
        checkedSavedProcesses = layout.presentProcesses(in: sections)
        applyLayout(sections)
    }

    /// Restores saved order once as each icon becomes available.
    private func layoutToRestore(from actual: [BarSection: [MenuBarItem]]) -> [BarSection: [MenuBarItem]]? {
        guard isAccessibilityGranted, let savedLayout, let dividers = controller.dividerFrames(),
              dividers.alwaysHidden.width > 0, dividers.hidden.width > 0,
              dividers.alwaysHidden.maxX < dividers.hidden.maxX else { return nil }
        let present = savedLayout.presentProcesses(in: actual)
        guard present.contains(where: { checkedSavedProcesses[$0.key] != $0.value }) else { return nil }
        checkedSavedProcesses.merge(present, uniquingKeysWith: { _, current in current })
        let restored = savedLayout.restoredSections(from: actual)
        // Unknown icons may be interleaved with saved ones without requiring a restart.
        let currentOrder = BarSection.allCases.map { actual[$0, default: []].map(\.layoutID).filter { present[$0] != nil } }
        let savedOrder = BarSection.allCases.map { restored[$0, default: []].map(\.layoutID).filter { present[$0] != nil } }
        return currentOrder == savedOrder ? nil : restored
    }

    /// Applies either a manual sort or a saved layout using the same system changes.
    private func applyLayout(_ sections: [BarSection: [MenuBarItem]]) {
        isSorting = true
        scanRevision += 1
        sortWarning = nil
        let arrangement = BarArrangement(
            alwaysHidden: sections[.alwaysHidden] ?? [],
            hidden: sections[.hidden] ?? [],
            shown: sections[.shown] ?? []
        )
        let fixed = fixedItems
        let widths = controller.ownWidths()

        Task {
            let failedNames = await LayoutSorter.apply(arrangement, fixedItems: fixed, ownWidths: widths)
            isSorting = false
            attemptedImageCaptures.removeAll()
            needsLiveCaptureBootstrap = true
            nextImageCaptureDate = .distantPast
            hasPendingChanges = false
            if !failedNames.isEmpty {
                sortWarning = "Could not move: " + failedNames.joined(separator: ", ")
            }
            refresh()
        }
    }

    // MARK: Private

    /// Section an icon belongs to, judged by its position relative to the dividers.
    private func section(for item: MenuBarItem) -> BarSection {
        guard let dividers = controller.dividerFrames() else { return .shown }
        let itemCenterX = item.frame.midX
        if itemCenterX < dividers.alwaysHidden.maxX { return .alwaysHidden }
        if itemCenterX < dividers.hidden.maxX { return .hidden }
        return .shown
    }

    /// Keeps the user's order for known icons, refreshes their data, drops gone ones and adds new ones.
    private func merged(arrangement: [BarSection: [MenuBarItem]], with scanned: [MenuBarItem]) -> [BarSection: [MenuBarItem]] {
        let scannedByID = Dictionary(scanned.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result = arrangement.mapValues { $0.compactMap { scannedByID[$0.id] } }
        let knownIDs = Set(result.values.joined().map(\.id))
        for item in scanned where !knownIDs.contains(item.id) {
            result[section(for: item), default: []].append(item)
        }
        return result
    }
}
