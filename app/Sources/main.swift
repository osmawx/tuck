import AppKit
import SwiftUI
#if canImport(Sparkle)
import Sparkle
#endif

/// Wires the status bar controller, the model, the hidden items panel and the layout window together.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private static let WINDOW_POLLING_CLIENT = "window"

    private var statusBarController: StatusBarController?
    private var barModel: BarModel?
    private var hiddenBarPanel: HiddenBarPanelController?
    private var layoutWindow: NSWindow?
#if canImport(Sparkle)
    private var updater: SPUStandardUpdaterController?
#endif

    /// Creates the status items, hidden panel, and layout window.
    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = StatusBarController()
        let model = BarModel(controller: controller)
        let panel = HiddenBarPanelController(model: model, controller: controller)
        controller.onOpenLayout = { [weak self] in self?.showLayoutWindow() }
        controller.onToggleHiddenBar = { panel.toggle() }
        statusBarController = controller
        barModel = model
        hiddenBarPanel = panel
#if canImport(Sparkle)
        let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.updater = updater
        controller.onCheckForUpdates = { [weak updater] in updater?.checkForUpdates(nil) }
#endif
        showLayoutWindow()
    }

    /// Re-opening the app from Finder or Spotlight brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showLayoutWindow()
        return true
    }

    /// Creates the window on first use and brings it to the front.
    func showLayoutWindow() {
        guard let barModel else { return }
        if layoutWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 820),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Menu Bar Layout"
            window.isReleasedWhenClosed = false
            let hostingView = NSHostingView(rootView: SettingsView(
                model: barModel,
                onCheckForUpdates: statusBarController?.onCheckForUpdates
            ))
            // Lets the SwiftUI toolbar and title reach the window.
            hostingView.sceneBridgingOptions = [.toolbars, .title]
            window.contentView = hostingView
            window.delegate = self
            window.center()
            layoutWindow = window
        }
        barModel.setPolling(true, client: Self.WINDOW_POLLING_CLIENT)
        NSApp.activate(ignoringOtherApps: true)
        layoutWindow?.makeKeyAndOrderFront(nil)
    }

    /// Stop rescanning once the window closes.
    func windowWillClose(_ notification: Notification) {
        barModel?.setPolling(false, client: Self.WINDOW_POLLING_CLIENT)
    }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let appDelegate = AppDelegate()
    application.delegate = appDelegate
    // Accessory = no Dock icon.
    application.setActivationPolicy(.accessory)
    application.run()
}
