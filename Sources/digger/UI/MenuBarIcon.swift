import AppKit
import CoreText

/// A template version of the app icon: a serif d cut out of a rounded tile.
/// Vector drawing keeps the small mark crisp at either menu-bar backing scale.
@MainActor
enum MenuBarIcon {
    static func makeImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            defer { context.restoreGState() }
            context.beginTransparencyLayer(auxiliaryInfo: nil)

            let tile = rect.insetBy(dx: 1, dy: 1)
            NSColor.black.setFill()
            NSBezierPath(roundedRect: tile, xRadius: 4, yRadius: 4).fill()

            let size = tile.height * 680 / 864
            let descriptor = NSFont.systemFont(ofSize: size, weight: .medium).fontDescriptor.withDesign(.serif)
            let font = descriptor.flatMap { NSFont(descriptor: $0, size: size) }
                ?? NSFont.systemFont(ofSize: size, weight: .medium)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: "d", attributes: [
                .font: font, .foregroundColor: NSColor.black
            ]))
            let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            context.textPosition = CGPoint(x: tile.midX - bounds.midX, y: tile.midY - bounds.midY)
            context.setBlendMode(.destinationOut)
            CTLineDraw(line, context)
            context.endTransparencyLayer()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = UIStrings.Menu.appTitle
        return image
    }
}
