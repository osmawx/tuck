import CoreGraphics

/// Rejects empty status-window snapshots before they replace a usable icon.
enum MenuBarImageValidation {
    /// Requires foreground contrast after compositing transparency on neutral gray.
    static func isUsable(_ image: CGImage) -> Bool {
        let width = min(image.width, 256)
        let height = min(image.height, 64)
        guard width > 1, height > 1,
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
                                          CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var histogram = [Int](repeating: 0, count: 256)
        for offset in stride(from: 0, to: width * height * 4, by: 4) {
            // RGB is premultiplied. Neutral backing also makes black transparent glyphs measurable.
            let backing = (255 - Int(pixels[offset + 3])) / 2
            let luminance = (54 * Int(pixels[offset]) + 183 * Int(pixels[offset + 1]) +
                             19 * Int(pixels[offset + 2])) / 256 + backing
            histogram[min(luminance, 255)] += 1
        }
        // Ignore isolated noise pixels; a valid glyph occupies more than one percent of the image.
        let tailCount = max(2, width * height / 100)
        var cumulative = 0
        var lower = 0
        var upper = 255
        for index in 0..<256 {
            cumulative += histogram[index]
            if cumulative >= tailCount { lower = index; break }
        }
        cumulative = 0
        for index in stride(from: 255, through: 0, by: -1) {
            cumulative += histogram[index]
            if cumulative >= tailCount { upper = index; break }
        }
        return upper - lower >= 48
    }
}
