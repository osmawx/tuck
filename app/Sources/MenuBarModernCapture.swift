import AppKit
import ScreenCaptureKit

/// Captures status item surfaces with ScreenCaptureKit when legacy snapshots are empty.
@MainActor
enum MenuBarModernCapture {
    private static var lastDiagnosticDates: [String: Date] = [:]

    /// Limits repeated capture messages while icons update continuously.
    private static func record(_ message: String) {
        let now = Date()
        guard now.timeIntervalSince(lastDiagnosticDates[message] ?? .distantPast) >= 60 else { return }
        lastDiagnosticDates[message] = now
        MenuDiagnostics.record(message)
    }

    /// Gets shared windows once per batch; never requests a new privacy permission.
    static func windows() async -> [SCWindow] {
        guard MenuBarImageCapture.isScreenRecordingGranted else { return [] }
        do {
            return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false).windows
        } catch {
            record("icon window enumeration failed: \((error as NSError).code)")
            return []
        }
    }

    /// Captures the source window first, then its visible menu bar rectangle if necessary.
    static func image(for item: MenuBarItem, window: SCWindow?, shouldContinue: () -> Bool) async -> NSImage? {
        guard shouldContinue(), MenuBarImageCapture.isScreenRecordingGranted else { return nil }
        if let window {
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = SCStreamConfiguration()
            let scale = CGFloat(filter.pointPixelScale)
            configuration.width = max(2, Int(window.frame.width * scale))
            configuration.height = max(2, Int(window.frame.height * scale))
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true
            configuration.ignoreGlobalClipSingleWindow = true
            configuration.shouldBeOpaque = false
            do {
                let captured = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                guard shouldContinue() else { return nil }
                if MenuBarImageValidation.isUsable(captured) {
                    record("icon captured with ScreenCaptureKit: \(item.id)")
                    return NSImage(cgImage: captured, size: window.frame.size)
                }
                record("icon window snapshot empty: \(item.id)")
            } catch {
                record("icon window capture failed: \(item.id), code=\((error as NSError).code)")
            }
        } else {
            record("icon window unavailable: \(item.id), frame=\(item.frame)")
        }

        // A region capture also works when Control Center does not publish a separate shared window.
        guard shouldContinue(), #available(macOS 15.2, *) else { return nil }
        let mainScreenTop = NSScreen.screens.first?.frame.maxY ?? 0
        let displays = NSScreen.screens.map {
            CGRect(x: $0.frame.minX, y: mainScreenTop - $0.frame.maxY,
                   width: $0.frame.width, height: $0.frame.height)
        }
        guard let bounds = MenuBarGeometry.visibleBounds(of: item.frame, on: displays) else {
            record("icon still outside displays after reveal: \(item.id), frame=\(item.frame)")
            return nil
        }
        do {
            let captured = try await SCScreenshotManager.captureImage(in: bounds)
            guard shouldContinue(), MenuBarImageValidation.isUsable(captured) else {
                record("icon region snapshot empty or cancelled: \(item.id)")
                return nil
            }
            record("icon captured from menu bar region: \(item.id)")
            return NSImage(cgImage: captured, size: bounds.size)
        } catch {
            record("icon region capture failed: \(item.id), code=\((error as NSError).code)")
            return nil
        }
    }
}
