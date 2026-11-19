import AppKit

/// Prepares tray glyphs for both the layout and the hidden-item panel.
enum MenuBarIconPresentation {
    static let GLYPH_HEIGHT: CGFloat = 16
    private static let APP_ICON_SIZE: CGFloat = 20

    /// Uses the captured glyph or the owning app's icon while capture is unavailable.
    static func image(for item: MenuBarItem) -> NSImage? {
        if let source = item.image, let glyph = image(from: source) { return glyph }
        if let appIcon = NSRunningApplication(processIdentifier: item.processIdentifier)?.icon?.copy() as? NSImage {
            appIcon.size = NSSize(width: APP_ICON_SIZE, height: APP_ICON_SIZE)
            return appIcon
        }
        return NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: item.displayName)
    }

    /// Removes captured backgrounds and padding, then scales without changing the aspect ratio.
    static func image(from source: NSImage) -> NSImage? {
        guard let bitmap = source.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let glyph = foreground(in: bitmap) else { return nil }
        let scale = GLYPH_HEIGHT / CGFloat(glyph.height)
        return NSImage(cgImage: glyph, size: NSSize(width: CGFloat(glyph.width) * scale, height: GLYPH_HEIGHT))
    }

    /// Leaves room for wide glyphs containing live text.
    static func buttonWidth(for source: NSImage?) -> CGFloat {
        max(48, (source.flatMap { image(from: $0) }?.size.width ?? APP_ICON_SIZE) + 16)
    }

    /// Extracts a transparent glyph from a window snapshot or a composited screen region.
    private static func foreground(in image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 1, height > 1,
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
                                          CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let corners = [0, (width - 1) * 4, (height - 1) * width * 4, (width * height - 1) * 4]
        // Transparent window captures have no matte to remove.
        let hasAlpha = corners.contains { pixels[$0 + 3] < 32 }
        let background = (0..<3).map { channel in
            corners.map { Int(pixels[$0 + channel]) }.sorted()[2]
        }
        var minimumX = width
        var minimumY = height
        var maximumX = -1
        var maximumY = -1
        for row in 0..<height {
            for column in 0..<width {
                let offset = (row * width + column) * 4
                if !hasAlpha {
                    removeMatte(pixels.advanced(by: offset), background: background)
                }
                guard pixels[offset + 3] > 16 else { continue }
                minimumX = min(minimumX, column)
                minimumY = min(minimumY, row)
                maximumX = max(maximumX, column)
                maximumY = max(maximumY, row)
            }
        }
        guard maximumX >= minimumX, maximumY >= minimumY else { return nil }
        return context.makeImage()?.cropping(to: CGRect(x: minimumX, y: minimumY,
            width: maximumX - minimumX + 1, height: maximumY - minimumY + 1))
    }

    /// Reconstructs premultiplied pixels so antialiased edges blend into the new background.
    private static func removeMatte(_ pixel: UnsafeMutablePointer<UInt8>, background: [Int]) {
        var alpha = 0
        for channel in 0..<3 {
            let matte = background[channel]
            let difference = Int(pixel[channel]) - matte
            let range = difference > 0 ? 255 - matte : matte
            if range > 0 { alpha = max(alpha, (abs(difference) * 255 + range - 1) / range) }
        }
        let contrast = (0..<3).map { abs(Int(pixel[$0]) - background[$0]) }.max() ?? 0
        if contrast <= 8 { alpha = 0 }
        for channel in 0..<3 {
            let premultiplied = Int(pixel[channel]) - background[channel] * (255 - alpha) / 255
            pixel[channel] = UInt8(clamping: min(alpha, premultiplied))
        }
        pixel[3] = UInt8(alpha)
    }
}
