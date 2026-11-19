import AppKit
import Combine
import SwiftUI

/// Bar under the menu bar that shows hidden icons when the dot is clicked.
@MainActor
final class HiddenBarPanelController {
    private static let POLLING_CLIENT = "panel"
    /// Gap between the menu bar and the panel.
    private static let MENU_BAR_GAP: CGFloat = 6
    private static let SCREEN_MARGIN: CGFloat = 8

    private let model: BarModel
    private let controller: StatusBarController
    private var panel: NSPanel?
    private var contentSize: CGSize?
    private var focusSubscriptions = Set<AnyCancellable>()
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    /// Stores the layout and menu controllers used by the panel.
    init(model: BarModel, controller: StatusBarController) {
        self.model = model
        self.controller = controller
    }

    var isVisible: Bool { panel?.isVisible == true }

    /// Opens the panel, or closes it when already open.
    func toggle() {
        isVisible ? close() : open()
    }

    /// Shows the panel under the dot.
    func open() {
        model.setPolling(true, client: Self.POLLING_CLIENT)
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()
        watchFocus()
    }

    /// Hides the panel.
    func close() {
        guard isVisible else { return }
        focusSubscriptions.removeAll()
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        localMouseMonitor = nil
        globalMouseMonitor = nil
        controller.dismissMenu()
        panel?.orderOut(nil)
        model.setPolling(false, client: Self.POLLING_CLIENT)
    }

    // MARK: Private

    /// Closes a nonactivating panel on app, Space, or window focus changes.
    private func watchFocus() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .merge(with: workspace.publisher(for: NSWorkspace.activeSpaceDidChangeNotification))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.close() }
            .store(in: &focusSubscriptions)

        NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
            .sink { [weak self] notification in
                guard let window = notification.object as? NSWindow, window.level == .normal else { return }
                self?.close()
            }
            .store(in: &focusSubscriptions)

        // A click in the already active app does not emit an activation notification.
        let mouseDown: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseDown) { [weak self] event in
            self?.closeOnOutsideClick(at: NSEvent.mouseLocation)
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseDown) { [weak self] _ in
            self?.closeOnOutsideClick(at: NSEvent.mouseLocation)
        }
    }

    /// Lets native menus track their own clicks and keeps the dot's toggle a single action.
    private func closeOnOutsideClick(at location: CGPoint) {
        guard !controller.isPresentingNativeMenu,
              panel?.frame.contains(location) != true,
              controller.toggleFrame?.contains(location) != true else { return }
        close()
    }

    /// Borderless, non-activating panel so the frontmost app keeps focus.
    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hostingView = NSHostingView(rootView: HiddenBarView(model: model, onContentSize: { [weak self] size in
            guard let self, size.width > 0, size.height > 0 else { return }
            guard self.contentSize != size else { return }
            self.contentSize = size
            if let panel = self.panel { self.position(panel) }
        }) { [weak self] item, button in
            guard let self, button.window != nil else { return }
            MenuDiagnostics.record("click: \(item.id)")
            Task {
                guard self.isVisible else { return }
                let opened = await self.controller.openMenu(for: item)
                if !opened && self.isVisible {
                    self.presentMenuError(self.controller.menuFailureMessage ?? "Не удалось открыть меню \(item.displayName). Подробности записаны в журнал Tuck.")
                }
            }
        })
        hostingView.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hostingView
        return panel
    }

    /// Displays failures in a system dialog instead of clipping text inside the icon strip.
    private func presentMenuError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Не удалось открыть меню"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// Right edge under the dot, kept inside the screen.
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.screens.first, let contentView = panel.contentView else { return }
        let size = contentSize ?? contentView.fittingSize
        let anchorX = controller.toggleFrame?.maxX ?? screen.frame.maxX
        let originX = min(max(anchorX - size.width, screen.frame.minX + Self.SCREEN_MARGIN), screen.frame.maxX - size.width - Self.SCREEN_MARGIN)
        let originY = screen.visibleFrame.maxY - size.height - Self.MENU_BAR_GAP
        panel.setFrame(NSRect(x: originX, y: originY, width: size.width, height: size.height), display: true)
    }
}

/// Row of hidden icons; native buttons accept the first click in a nonactivating panel.
private struct HiddenBarView: View {
    @ObservedObject var model: BarModel
    let onContentSize: (CGSize) -> Void
    let onPress: (MenuBarItem, NSView) -> Void

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                let items = model.sections[.hidden] ?? []
                if items.isEmpty {
                    Text("No hidden items").font(.callout).padding(.horizontal, 8)
                }
                ForEach(items) { item in
                    HiddenItemButton(item: item) { button in onPress(item, button) }
                        .frame(width: MenuBarIconPresentation.buttonWidth(for: item.image), height: 34)
                }
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .fixedSize()
        .background(GeometryReader { geometry in
            Color.clear.preference(key: HiddenBarSizeKey.self, value: geometry.size)
                .allowsHitTesting(false)
        })
        .onPreferenceChange(HiddenBarSizeKey.self, perform: onContentSize)
    }
}

/// Reports the full intrinsic size of the icon strip.
private struct HiddenBarSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    /// Uses the size reported by the root content view.
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// AppKit button with a stable target and a screen-space anchor for its menu.
private struct HiddenItemButton: NSViewRepresentable {
    let item: MenuBarItem
    let onPress: (NSView) -> Void

    /// Creates the retained target used by AppKit's action dispatch.
    func makeCoordinator() -> Coordinator { Coordinator(onPress: onPress) }

    /// Creates a borderless button that accepts clicks without activating the panel.
    func makeNSView(context: Context) -> NSButton {
        let button = FirstClickButton()
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.target = context.coordinator
        button.action = #selector(Coordinator.press(_:))
        return button
    }

    /// Refreshes the icon and callback while preserving the native button instance.
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.onPress = onPress
        let sourceImage = MenuBarIconPresentation.image(for: item)
        button.imagePosition = sourceImage == nil ? .noImage : .imageOnly
        button.title = sourceImage == nil ? item.displayName : ""
        button.image = sourceImage
        button.toolTip = item.displayName
        button.setAccessibilityLabel(item.displayName)
    }

    /// Retains the closure that AppKit calls for a button press.
    final class Coordinator: NSObject {
        var onPress: (NSView) -> Void

        /// Stores the current button callback.
        init(onPress: @escaping (NSView) -> Void) { self.onPress = onPress }

        /// Dispatches a native button action with its exact view anchor.
        @objc func press(_ sender: NSButton) { onPress(sender) }
    }
}

/// Receives the first click even while another app remains active.
private final class FirstClickButton: NSButton {
    /// Allows one click to trigger the action without an activation click first.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
