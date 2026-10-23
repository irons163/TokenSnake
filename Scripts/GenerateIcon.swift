import AppKit
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let arguments = Array(CommandLine.arguments.dropFirst())
let outDir = arguments.first.map { URL(fileURLWithPath: $0) }
    ?? root.appending(path: "TokenSnake/Assets.xcassets")
let source = arguments.dropFirst().first.map { URL(fileURLWithPath: $0) }
    ?? root.appending(path: "Design/AppIcon/TokenSnakeIcon-v4.png")
let iconset = outDir.appending(path: "AppIcon.appiconset")

guard let imageData = try? Data(contentsOf: source),
      let sourceRep = NSBitmapImageRep(data: imageData),
      sourceRep.pixelsWide == sourceRep.pixelsHigh,
      sourceRep.pixelsWide >= 1024,
      sourceRep.hasAlpha,
      let master = NSImage(data: imageData) else {
    throw NSError(domain: "TokenSnake.Icon", code: 1,
                  userInfo: [NSLocalizedDescriptionKey: "Expected a square transparent PNG master of at least 1024 pixels: \(source.path)"])
}
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func writePNG(pixels: Int, to url: URL) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 32
    ) else { throw NSError(domain: "TokenSnake.Icon", code: 2) }
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    NSColor.clear.setFill()
    rect.fill(using: .copy)
    master.draw(in: rect, from: .zero, operation: .copy, fraction: 1,
                respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high.rawValue])
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "TokenSnake.Icon", code: 3)
    }
    try data.write(to: url, options: .atomic)
}

// Preserve the generated master; only resample it for the asset catalog.
let sizes = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
             (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []
for (size, scale) in sizes {
    let filename = "icon_\(size)@\(scale)x.png"
    try writePNG(pixels: size * scale, to: iconset.appending(path: filename))
    images.append(["filename": filename, "idiom": "mac", "scale": "\(scale)x", "size": "\(size)x\(size)"])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: iconset.appending(path: "Contents.json"), options: .atomic)
print("Generated 10 macOS icon assets from \(source.path)")
