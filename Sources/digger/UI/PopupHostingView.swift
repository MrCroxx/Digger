import AppKit
import SwiftUI

/// Let AppKit own the popup size while SwiftUI renders its contents.
final class PopupHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        // AppKit and the user's resize gesture own the panel size, never a
        // transient intrinsic/minimum size from a partial Markdown snapshot.
        sizingOptions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

}

/// Configure the actual enclosing scroller as soon as SwiftUI inserts content.
/// A hosting-view layout callback is not guaranteed for every streamed update.
struct PopupScrollStyle: NSViewRepresentable {
    func makeNSView(context: Context) -> Marker { Marker() }
    func updateNSView(_ view: Marker, context: Context) { view.configureScroller() }

    final class Marker: NSView {
        private weak var observedScrollView: NSScrollView?
        private var styleObservation: NSKeyValueObservation?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); configureScroller() }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); configureScroller() }

        func configureScroller() {
            guard let scrollView = enclosingScrollView else { return }
            if observedScrollView !== scrollView {
                observedScrollView = scrollView
                // SwiftUI/AppKit may restore the preferred style after insertion.
                // Keep that change from temporarily consuming viewport width.
                styleObservation = scrollView.observe(\.scrollerStyle) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.configureScroller() }
                }
            }
            if scrollView.scrollerStyle != .overlay { scrollView.scrollerStyle = .overlay }
            if !scrollView.autohidesScrollers { scrollView.autohidesScrollers = true }
            if let scroller = scrollView.verticalScroller, !(scroller is PopupScroller) {
                scrollView.verticalScroller = PopupScroller(replacing: scroller)
            }
            if let scroller = scrollView.horizontalScroller, !(scroller is PopupScroller) {
                scrollView.horizontalScroller = PopupScroller(replacing: scroller)
            }
        }
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
