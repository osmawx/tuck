import AppKit

/// Takes pictures of menu bar item windows (needs Screen Recording access).
///
/// `CGWindowListCreateImage` is hidden from Swift since the macOS 15 SDK but still works at runtime
/// and, unlike ScreenCaptureKit, also captures windows that sit off screen (our hidden items).
enum MenuBarImageCapture {
    private typealias CreateImageFunction = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    /// kCGWindowListOptionIncludingWindow.
    private static let OPTION_INCLUDING_WINDOW: UInt32 = 1 << 3
    /// kCGWindowImageBoundsIgnoreFraming | kCGWindowImageBestResolution.
    private static let IMAGE_OPTIONS: UInt32 = (1 << 0) | (1 << 3)

    private static let createImage: CreateImageFunction? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
              let symbol = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        return unsafeBitCast(symbol, to: CreateImageFunction.self)
    }()

    /// True when the system lets this app read other windows' pixels.
    static var isScreenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system Screen Recording prompt (once per app build).
    static func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }

    /// Collects display geometry in Core Graphics coordinates.
    @MainActor
    static func displayBounds() -> [CGRect] {
        let mainScreenTop = NSScreen.screens.first?.frame.maxY ?? 0
        return NSScreen.screens.map {
            CGRect(x: $0.frame.minX, y: mainScreenTop - $0.frame.maxY,
                   width: $0.frame.width, height: $0.frame.height)
        }
    }

    /// Captures a visible region using display geometry collected on the main actor.
    static func image(in frame: CGRect, displays: [CGRect]) -> NSImage? {
        guard let createImage,
              let bounds = MenuBarGeometry.visibleBounds(of: frame, on: displays),
              let captured = createImage(bounds, 1, kCGNullWindowID, IMAGE_OPTIONS)?.takeRetainedValue(),
              MenuBarImageValidation.isUsable(captured) else { return nil }
        return NSImage(cgImage: captured, size: bounds.size)
    }

    /// Captures one status window using the caller's display scale.
    static func image(of windowID: CGWindowID, scale: CGFloat) -> NSImage? {
        guard let createImage,
              let cgImage = createImage(.null, OPTION_INCLUDING_WINDOW, windowID, IMAGE_OPTIONS)?.takeRetainedValue(),
              MenuBarImageValidation.isUsable(cgImage) else { return nil }
        // Images come at pixel size; divide by the screen scale to get points.
        return NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale))
    }
}
