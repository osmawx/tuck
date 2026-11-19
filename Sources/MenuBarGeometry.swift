import CoreGraphics

/// Geometry shared by native menu activation and icon capture; coordinates use a top-left origin.
enum MenuBarGeometry {
    /// Clips harmless vertical window padding while rejecting horizontally hidden status items.
    static func visibleBounds(of frame: CGRect, on displays: [CGRect]) -> CGRect? {
        guard frame.width > 0, frame.height > 0 else { return nil }
        for display in displays {
            let visible = display.intersection(frame)
            if frame.minX >= display.minX - 0.5,
               frame.maxX <= display.maxX + 0.5,
               display.contains(CGPoint(x: frame.midX, y: frame.midY)),
               visible.height >= frame.height / 2 {
                return visible
            }
        }
        return nil
    }
}
