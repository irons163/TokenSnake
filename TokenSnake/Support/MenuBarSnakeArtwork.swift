import AppKit

/// A pixel-sized template drawn from vectors, matching the App icon's S-shaped snake.
/// Clear eye and token details reveal the menu bar underneath in either appearance.
enum MenuBarSnakeArtwork {
    static let pointSize: CGFloat = 18

    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize))
        for scale in [1, 2, 3] {
            let pixels = Int(pointSize) * scale
            guard let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32
            ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { continue }
            bitmap.size = image.size
            let context = graphics.cgContext
            context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
            context.translateBy(x: 0, y: CGFloat(pixels))
            context.scaleBy(x: CGFloat(pixels) / 20, y: -CGFloat(pixels) / 20)
            draw(in: context)
            image.addRepresentation(bitmap)
        }
        image.isTemplate = true
        image.accessibilityDescription = "TokenSnake 小蛇與 T token"
        return image
    }()

    private static func draw(in context: CGContext) {
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setStrokeColor(NSColor.black.cgColor)
        context.setFillColor(NSColor.black.cgColor)
        context.setLineWidth(2.7)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        // One broad S curve and an open lower coil leave room for the token.
        let body = CGMutablePath()
        body.move(to: CGPoint(x: 4.5, y: 11.7))
        body.addCurve(to: CGPoint(x: 4.8, y: 17), control1: CGPoint(x: 1.4, y: 12.7), control2: CGPoint(x: 2, y: 16.2))
        body.addCurve(to: CGPoint(x: 14.7, y: 14.1), control1: CGPoint(x: 8.7, y: 19.3), control2: CGPoint(x: 16, y: 17.5))
        body.addCurve(to: CGPoint(x: 9.4, y: 9), control1: CGPoint(x: 14.3, y: 11.2), control2: CGPoint(x: 11.5, y: 10))
        body.addCurve(to: CGPoint(x: 6.4, y: 6), control1: CGPoint(x: 7.5, y: 8), control2: CGPoint(x: 5.8, y: 7.7))
        body.addCurve(to: CGPoint(x: 10, y: 3.7), control1: CGPoint(x: 6.3, y: 4.4), control2: CGPoint(x: 7.9, y: 3.7))
        body.addCurve(to: CGPoint(x: 14.2, y: 3.8), control1: CGPoint(x: 11.3, y: 3.4), control2: CGPoint(x: 13.2, y: 3.4))
        context.addPath(body)
        context.strokePath()

        let head = CGMutablePath()
        head.move(to: CGPoint(x: 11.3, y: 2.4))
        head.addCurve(to: CGPoint(x: 16.4, y: 2.6), control1: CGPoint(x: 13.5, y: 1.3), control2: CGPoint(x: 15.4, y: 1.7))
        head.addCurve(to: CGPoint(x: 18.3, y: 3.7), control1: CGPoint(x: 17, y: 3.2), control2: CGPoint(x: 18.3, y: 3.1))
        head.addCurve(to: CGPoint(x: 16.6, y: 6.3), control1: CGPoint(x: 19, y: 5.1), control2: CGPoint(x: 18, y: 6.2))
        head.addCurve(to: CGPoint(x: 11.3, y: 5.3), control1: CGPoint(x: 14.2, y: 6.7), control2: CGPoint(x: 12.3, y: 5.8))
        head.closeSubpath()
        context.addPath(head)
        context.fillPath()

        let token = CGMutablePath()
        for corner in 0..<6 {
            let angle = CGFloat(corner) * .pi / 3 - .pi / 2
            let point = CGPoint(x: 8.3 + cos(angle) * 2.25, y: 13.5 + sin(angle) * 2.25)
            if corner == 0 { token.move(to: point) } else { token.addLine(to: point) }
        }
        token.closeSubpath()
        context.addPath(token)
        context.fillPath()

        // Knockouts remain transparent; an opaque white eye would fail in light mode.
        context.setBlendMode(.clear)
        context.fillEllipse(in: CGRect(x: 14.8, y: 2.8, width: 1.35, height: 1.35))
        context.fill(CGRect(x: 7, y: 12, width: 2.6, height: 1))
        context.fill(CGRect(x: 7.8, y: 12.8, width: 1, height: 2.2))
    }
}
