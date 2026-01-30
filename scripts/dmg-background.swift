import AppKit

struct DMGBackgroundRenderer {
    let outputPath: String
    let appName: String
    let width: Int
    let height: Int
    let scale: Int

    func render() throws {
        let size = NSSize(width: width, height: height)
        let scaleFactor = max(1, scale)
        let pixelWidth = width * scaleFactor
        let pixelHeight = height * scaleFactor
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw NSError(domain: "dmg-background", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create bitmap context"])
        }

        bitmap.size = size

        let context = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context?.imageInterpolation = .high
        context?.shouldAntialias = true

        let rect = NSRect(origin: .zero, size: size)
        drawBackground(in: rect)
        drawArrow(in: rect)
        drawText(in: rect)

        NSGraphicsContext.restoreGraphicsState()

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "dmg-background", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG data"])
        }

        let url = URL(fileURLWithPath: outputPath)
        try pngData.write(to: url)
    }

    private func drawBackground(in rect: NSRect) {
        let top = NSColor(calibratedRed: 0.98, green: 0.97, blue: 0.95, alpha: 1)
        let bottom = NSColor(calibratedRed: 0.94, green: 0.93, blue: 0.90, alpha: 1)
        let gradient = NSGradient(starting: top, ending: bottom)
        gradient?.draw(in: rect, angle: -90)

        let insetRect = rect.insetBy(dx: 10, dy: 10)
        let border = NSBezierPath(roundedRect: insetRect, xRadius: 18, yRadius: 18)
        NSColor(calibratedWhite: 0.86, alpha: 1).setStroke()
        border.lineWidth = 1
        border.stroke()
    }

    private func drawArrow(in rect: NSRect) {
        let arrowColor = NSColor(calibratedRed: 0.78, green: 0.60, blue: 0.36, alpha: 1)
        arrowColor.setStroke()

        let midY = rect.midY + 10
        let startX = rect.midX - 90
        let endX = rect.midX + 90

        let path = NSBezierPath()
        path.move(to: NSPoint(x: startX, y: midY))
        path.line(to: NSPoint(x: endX, y: midY))
        path.lineWidth = 6
        path.lineCapStyle = .round
        path.stroke()

        let head = NSBezierPath()
        head.move(to: NSPoint(x: endX, y: midY))
        head.line(to: NSPoint(x: endX - 18, y: midY + 12))
        head.move(to: NSPoint(x: endX, y: midY))
        head.line(to: NSPoint(x: endX - 18, y: midY - 12))
        head.lineWidth = 6
        head.lineCapStyle = .round
        head.stroke()
    }

    private func drawText(in rect: NSRect) {
        let title = "Drag \(appName) to Applications"
        let subtitle = "Install by dragging the app"

        let titleFont = NSFont(name: "Avenir Next DemiBold", size: 20) ?? NSFont.systemFont(ofSize: 20, weight: .semibold)
        let subtitleFont = NSFont(name: "Avenir Next Regular", size: 13) ?? NSFont.systemFont(ofSize: 13, weight: .regular)

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor(calibratedWhite: 0.20, alpha: 1)
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: subtitleFont,
            .foregroundColor: NSColor(calibratedWhite: 0.35, alpha: 1)
        ]

        let titleSize = (title as NSString).size(withAttributes: titleAttributes)
        let subtitleSize = (subtitle as NSString).size(withAttributes: subtitleAttributes)

        let titlePoint = NSPoint(x: rect.midX - titleSize.width / 2, y: rect.maxY - 80)
        let subtitlePoint = NSPoint(x: rect.midX - subtitleSize.width / 2, y: rect.maxY - 105)

        (title as NSString).draw(at: titlePoint, withAttributes: titleAttributes)
        (subtitle as NSString).draw(at: subtitlePoint, withAttributes: subtitleAttributes)
    }
}

let args = CommandLine.arguments
guard args.count >= 5,
      let width = Int(args[3]),
      let height = Int(args[4]) else {
    fputs("Usage: dmg-background.swift <output-path> <app-name> <width> <height> [scale]\n", stderr)
    exit(1)
}

let scale = args.count >= 6 ? (Int(args[5]) ?? 1) : 1

let renderer = DMGBackgroundRenderer(
    outputPath: args[1],
    appName: args[2],
    width: width,
    height: height,
    scale: scale
)

do {
    try renderer.render()
} catch {
    fputs("Failed to render DMG background: \(error)\n", stderr)
    exit(1)
}
