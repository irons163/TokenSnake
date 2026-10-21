import AppKit
import Foundation

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "TokenSnake/Assets.xcassets")
let iconset = outDir.appending(path: "AppIcon.appiconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func draw(in rect: NSRect) {
    let size = rect.width
    let radius = size * 0.223
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSColor(calibratedRed: 0.055, green: 0.075, blue: 0.058, alpha: 1).setFill()
    path.fill()

    let glow = NSBezierPath(ovalIn: NSRect(x: size * 0.18, y: size * 0.42, width: size * 0.62, height: size * 0.42))
    NSColor(calibratedRed: 0.18, green: 0.55, blue: 0.32, alpha: 0.45).setFill()
    glow.fill()

    let token = NSBezierPath()
    let cx = size * 0.50
    let cy = size * 0.46
    let outer = size * 0.20
    for i in 0..<6 {
        let angle = CGFloat(i) * .pi / 3 - .pi / 2
        let point = NSPoint(x: cx + cos(angle) * outer, y: cy + sin(angle) * outer)
        if i == 0 { token.move(to: point) } else { token.line(to: point) }
    }
    token.close()
    NSColor(calibratedRed: 0.12, green: 0.18, blue: 0.13, alpha: 1).setFill()
    token.fill()
    NSColor(calibratedRed: 0.38, green: 0.96, blue: 0.56, alpha: 0.85).setStroke()
    token.lineWidth = max(1.5, size * 0.018)
    token.stroke()

    let snake = NSBezierPath()
    snake.move(to: NSPoint(x: size * 0.18, y: size * 0.32))
    snake.curve(
        to: NSPoint(x: size * 0.46, y: size * 0.58),
        controlPoint1: NSPoint(x: size * 0.16, y: size * 0.58),
        controlPoint2: NSPoint(x: size * 0.32, y: size * 0.18)
    )
    snake.curve(
        to: NSPoint(x: size * 0.78, y: size * 0.62),
        controlPoint1: NSPoint(x: size * 0.58, y: size * 0.90),
        controlPoint2: NSPoint(x: size * 0.66, y: size * 0.30)
    )
    NSColor(calibratedRed: 0.38, green: 0.96, blue: 0.56, alpha: 1).setStroke()
    snake.lineWidth = max(2, size * 0.07)
    snake.lineCapStyle = .round
    snake.lineJoinStyle = .round
    snake.stroke()

    let head = NSBezierPath(ovalIn: NSRect(x: size * 0.72, y: size * 0.54, width: size * 0.14, height: size * 0.14))
    NSColor(calibratedRed: 0.38, green: 0.96, blue: 0.56, alpha: 1).setFill()
    head.fill()
    let eye = NSBezierPath(ovalIn: NSRect(x: size * 0.80, y: size * 0.60, width: size * 0.035, height: size * 0.035))
    NSColor(calibratedRed: 0.04, green: 0.06, blue: 0.04, alpha: 1).setFill()
    eye.fill()
}

func writePNG(pixels: Int, to url: URL) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 32
    ) else {
        throw NSError(domain: "TokenSnake", code: 1)
    }
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(in: NSRect(x: 0, y: 0, width: CGFloat(pixels), height: CGFloat(pixels)))
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "TokenSnake", code: 2)
    }
    try data.write(to: url)
}

let existing = try FileManager.default.contentsOfDirectory(at: iconset, includingPropertiesForKeys: nil)
for file in existing where file.pathExtension == "png" {
    try? FileManager.default.removeItem(at: file)
}

let sizes: [(Int, Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2)
]

var images: [[String: String]] = []
for (size, scale) in sizes {
    let pixel = size * scale
    let filename = "icon_\(size)@\(scale)x.png"
    try writePNG(pixels: pixel, to: iconset.appending(path: filename))
    images.append([
        "filename": filename,
        "idiom": "mac",
        "scale": "\(scale)x",
        "size": "\(size)x\(size)"
    ])
}

let contents: [String: Any] = [
    "images": images,
    "info": ["author": "xcode", "version": 1]
]
let data = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try data.write(to: iconset.appending(path: "Contents.json"))
print("Wrote AppIcon to \(iconset.path)")
