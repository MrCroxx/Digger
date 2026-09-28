import AppKit
import Testing
@testable import digger

@MainActor
struct RegionScreenshotTests {
    @Test func selectionWorksInEitherDirectionAndClipsToDisplay() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        #expect(RegionPickerView.selectionRect(from: CGPoint(x: 500, y: 450), to: CGPoint(x: 100, y: 80), bounds: bounds)
                == CGRect(x: 100, y: 80, width: 400, height: 370))
        #expect(RegionPickerView.selectionRect(from: CGPoint(x: 100, y: 80), to: CGPoint(x: 500, y: 450), bounds: bounds)
                == CGRect(x: 100, y: 80, width: 400, height: 370))
        #expect(RegionPickerView.selectionRect(from: CGPoint(x: 100, y: 80), to: CGPoint(x: 900, y: -50), bounds: bounds)
                == CGRect(x: 100, y: 0, width: 700, height: 80))
    }

    @Test func maskLeavesSelectionClearAndEscapeCancels() throws {
        let view = RegionPickerView(frame: CGRect(x: 0, y: 0, width: 640, height: 400))
        func event(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        view.mouseDown(with: try event(.leftMouseDown, CGPoint(x: 100, y: 100)))
        view.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: 450, y: 300)))
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 400,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
        #expect(try #require(bitmap.colorAt(x: 20, y: 20)).alphaComponent > 0.4)
        #expect(try #require(bitmap.colorAt(x: 200, y: 200)).alphaComponent == 0)
        var cancelled = false
        view.onFinish = { cancelled = $0 == nil }
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        view.keyDown(with: escape)
        #expect(cancelled)
    }
}
