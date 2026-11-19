import ServiceManagement
import SwiftUI

/// Main window: header, sort row, permission rows, three icon sections.
struct SettingsView: View {
    @ObservedObject var model: BarModel
    let onCheckForUpdates: (() -> Void)?
    @State private var isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                SectionHeading(title: "On-Demand Layout", symbolName: "arrow.up.arrow.down.square")
                sortRow
                if !model.isAccessibilityGranted {
                    ActionRow(
                        symbolName: "hand.raised.fill", tint: .orange,
                        text: "Accessibility access is needed to find and open menu bar items.",
                        buttonTitle: "Grant Access", action: model.requestAccessibility
                    )
                }
                if !model.isScreenRecordingGranted {
                    ActionRow(
                        symbolName: "camera.viewfinder", tint: .purple,
                        text: "Screen Recording access shows real menu bar icons instead of app icons.",
                        buttonTitle: "Grant Access", action: model.requestScreenRecording
                    )
                }
                ForEach(BarSection.allCases) { section in
                    SectionHeading(title: section.title, symbolName: section.symbolName)
                    SectionRow(section: section, model: model)
                }
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                    .padding(.top, 6)
            }
            .padding(24)
        }
        .frame(minWidth: 640, minHeight: 760)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Menu Bar Layout")
        .toolbar {
            if let onCheckForUpdates {
                ToolbarItem {
                    Button("Check for Updates…", action: onCheckForUpdates)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: model.refresh) { Image(systemName: "arrow.clockwise") }
                    .help("Rescan the menu bar")
            }
        }
    }

    // MARK: Parts

    /// Title card with the app glyph.
    private var header: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 22)
                .fill(LinearGradient(colors: [Color(white: 0.72), Color(white: 0.55)], startPoint: .top, endPoint: .bottom))
                .frame(width: 96, height: 96)
                .overlay(Image(systemName: "menubar.rectangle").font(.system(size: 46, weight: .regular)).foregroundStyle(.white))
            Text("Menu Bar Items").font(.system(size: 34, weight: .bold))
            Text("Drag items between sections to re-order your menu bar.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.primary.opacity(0.04)))
    }

    /// "Sort My Bar" row; it also shows progress and failures of the last sort.
    private var sortRow: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: "square.grid.3x3.fill").foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text(sortRowText).foregroundStyle(.secondary)
                if let warning = model.sortWarning {
                    Text(warning).font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            if model.hasPendingChanges && !model.isSorting {
                Button("Revert", action: model.revertChanges).buttonStyle(.link)
            }
            if model.isSorting {
                ProgressView().controlSize(.small)
            }
            Button(action: model.sortMyBar) {
                Text("Sort My Bar").font(.title3.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 6)
            }
            .buttonStyle(CapsuleButtonStyle())
            .disabled(model.isSorting || !model.isAccessibilityGranted)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.primary.opacity(0.04)))
    }

    private var sortRowText: String {
        if model.isSorting { return "Sorting… the menu bar blinks once while Control Center restarts." }
        if model.hasPendingChanges { return "Layout changed. Click Sort My Bar to apply it." }
        return "Lay out your items, then click Sort My Bar to organize."
    }

    /// Binding that registers or unregisters the login item as the switch flips.
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { isLaunchAtLoginEnabled },
            set: { newValue in
                do {
                    if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    NSAlert(error: error).runModal()
                }
                isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            }
        )
    }
}

/// Icon + title above each block.
private struct SectionHeading: View {
    let title: String
    let symbolName: String

    var body: some View {
        Label {
            Text(title).font(.title3)
        } icon: {
            Image(systemName: NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) == nil ? "eye.slash" : symbolName)
        }
        .padding(.top, 6)
    }
}

/// Row with an icon, a sentence and one button (permissions).
private struct ActionRow: View {
    let symbolName: String
    let tint: Color
    let text: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Circle().fill(tint).frame(width: 44, height: 44)
                .overlay(Image(systemName: symbolName).foregroundStyle(.white))
            Text(text).foregroundStyle(.secondary)
            Spacer()
            Button(action: action) { Text(buttonTitle).padding(.horizontal, 10).padding(.vertical, 4) }
                .buttonStyle(CapsuleButtonStyle())
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.primary.opacity(0.04)))
    }
}

/// Blue capsule like the system's prominent buttons.
private struct CapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    /// Draws the enabled and pressed states of the capsule button.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(Capsule().fill(Color.accentColor.opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)))
    }
}
