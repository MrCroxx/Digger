import AppKit
import SwiftUI

/// Keep SwiftUI's native scrolling, with popup-specific overlay scrollers.
final class PopupHostingView<Content: View>: NSHostingView<Content> {
    override func layout() {
        super.layout()
        styleScrollViews(in: self)
    }

    private func styleScrollViews(in view: NSView) {
        if let scrollView = view as? NSScrollView {
            if scrollView.scrollerStyle != .overlay { scrollView.scrollerStyle = .overlay }
            if !scrollView.autohidesScrollers { scrollView.autohidesScrollers = true }
            if let scroller = scrollView.verticalScroller, !(scroller is PopupScroller) {
                scrollView.verticalScroller = PopupScroller(replacing: scroller)
            }
            if let scroller = scrollView.horizontalScroller, !(scroller is PopupScroller) {
                scrollView.horizontalScroller = PopupScroller(replacing: scroller)
            }
        }
        for child in view.subviews { styleScrollViews(in: child) }
    }
}

/// Draw a narrow thumb inside the native hit area. AppKit still owns dragging,
/// momentum scrolling, accessibility and the overlay's fade animation.
private final class PopupScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    convenience init(replacing scroller: NSScroller) {
        self.init(frame: scroller.frame)
        controlSize = .small
        scrollerStyle = .overlay
        target = scroller.target
        action = scroller.action
        doubleValue = scroller.doubleValue
        knobProportion = scroller.knobProportion
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    override func drawKnob() {
        var thumb = rect(for: .knob)
        guard !thumb.isEmpty else { return }
        let thickness: CGFloat = 4
        if bounds.height > bounds.width {
            thumb.origin.x = thumb.midX - thickness / 2
            thumb.size.width = thickness
        } else {
            thumb.origin.y = thumb.midY - thickness / 2
            thumb.size.height = thickness
        }
        NSColor.secondaryLabelColor.withAlphaComponent(0.45).setFill()
        NSBezierPath(roundedRect: thumb, xRadius: thickness / 2, yRadius: thickness / 2).fill()
    }
}
