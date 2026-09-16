#!/usr/bin/env swift
import AppKit
import CoreText

// Rebuild the app icon from the same serif monogram and brown used by BrandMark.
// Usage: swift scripts/app-icon.swift
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Sources/digger/Resources")
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
let iconset = temporary.appendingPathComponent("Digger.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }

func render(pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }
    let cg = context.cgContext
    cg.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    let tile = NSRect(x: 80, y: 80, width: 864, height: 864)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 210, yRadius: 210)
    cg.saveGState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor(srgbRed: 128 / 255, green: 85 / 255, blue: 56 / 255, alpha: 1).setFill()
    shape.fill()
    cg.restoreGState()

    let descriptor = NSFont.systemFont(ofSize: 680, weight: .medium).fontDescriptor.withDesign(.serif)!
    let font = NSFont(descriptor: descriptor, size: 680)!
    let text = NSAttributedString(string: "d", attributes: [
        .font: font,
        .foregroundColor: NSColor(srgbRed: 1, green: 248 / 255, blue: 237 / 255, alpha: 1)
    ])
    let line = CTLineCreateWithAttributedString(text)
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    cg.textPosition = CGPoint(x: tile.midX - bounds.midX, y: tile.midY - bounds.midY)
    CTLineDraw(line, cg)
    return bitmap.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let data = render(pixels: size * scale)
        try data.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
try render(pixels: 1024).write(to: resources.appendingPathComponent("digger.png"))
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Updated digger.png and AppIcon.icns")
