import AppKit

/// Draws text over the exact Finder window bounds used by the disk image layout.
func drawLabel(_ text: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    (text as NSString).draw(at: point, withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color
    ])
}

/// Creates the installation instructions and drag direction for Finder's background.
func makeBackground() -> NSImage {
    let canvas = NSSize(width: 660, height: 530)
    return NSImage(size: canvas, flipped: true) { bounds in
        let ink = NSColor(srgbRed: 0.08, green: 0.13, blue: 0.22, alpha: 1)
        let secondary = NSColor(srgbRed: 0.23, green: 0.29, blue: 0.38, alpha: 1)
        let divider = NSColor(srgbRed: 0.80, green: 0.83, blue: 0.88, alpha: 1)
        NSColor(srgbRed: 0.93, green: 0.95, blue: 0.98, alpha: 1).setFill()
        NSBezierPath(rect: bounds).fill()

        drawLabel("Установка Tuck", at: NSPoint(x: 44, y: 27), size: 26, weight: .bold, color: ink)
        drawLabel("Перетащи Tuck.app в «Программы» и открой его оттуда.",
                  at: NSPoint(x: 44, y: 67), size: 15, weight: .regular, color: secondary)

        NSColor(srgbRed: 0.16, green: 0.36, blue: 0.70, alpha: 1).setStroke()
        let arrow = NSBezierPath()
        arrow.lineWidth = 3
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        arrow.move(to: NSPoint(x: 296, y: 145))
        arrow.line(to: NSPoint(x: 364, y: 145))
        arrow.move(to: NSPoint(x: 352, y: 133))
        arrow.line(to: NSPoint(x: 364, y: 145))
        arrow.line(to: NSPoint(x: 352, y: 157))
        arrow.stroke()

        divider.setFill()
        NSBezierPath(rect: NSRect(x: 44, y: 222, width: 572, height: 1)).fill()
        drawLabel("Если macOS заблокировала первый запуск", at: NSPoint(x: 44, y: 238),
                  size: 17, weight: .semibold, color: ink)
        drawLabel("Открой «Настройки безопасности» двойным щелчком.",
                  at: NSPoint(x: 44, y: 268), size: 15, weight: .regular, color: secondary)
        drawLabel("В разделе «Безопасность» нажми «Открыть всё равно».",
                  at: NSPoint(x: 44, y: 292), size: 15, weight: .regular, color: secondary)
        return true
    }
}

/// Renders at a fixed pixel density, independent of the build machine's display.
func writeBackground(_ image: NSImage, scale: Int, to output: URL) throws {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(image.size.width) * scale,
        pixelsHigh: Int(image.size.height) * scale,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )
    guard let bitmap, let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSAffineTransform(transform: AffineTransform(scale: CGFloat(scale))).concat()
    image.draw(in: NSRect(origin: .zero, size: image.size))
    NSGraphicsContext.restoreGraphicsState()

    bitmap.size = image.size
    guard let tiff = bitmap.tiffRepresentation else {
        throw CocoaError(.fileWriteUnknown)
    }
    try tiff.write(to: output)
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: draw-background.swift <output-directory>\n".utf8))
    exit(1)
}

let background = makeBackground()
background.cacheMode = .never
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try writeBackground(background, scale: 1, to: outputDirectory.appendingPathComponent("background.tiff"))
try writeBackground(background, scale: 2, to: outputDirectory.appendingPathComponent("background@2x.tiff"))
