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
    var followsStreaming = false
    var requestID: UUID?
    var defersFollowing: () -> Bool = { false }
    func makeNSView(context: Context) -> Marker { Marker() }
    func updateNSView(_ view: Marker, context: Context) {
        view.update(followsStreaming: followsStreaming, requestID: requestID, defersFollowing: defersFollowing)
    }

    final class Marker: NSView {
        private weak var observedScrollView: NSScrollView?
        private var styleObservation: NSKeyValueObservation?
        private var followsStreaming = false
        private var followFinalLayout = false
        private var followsBottom = true
        private var requestID: UUID?
        private var previousHeight: CGFloat = 0
        private var previousOrigin: CGFloat = 0
        private var previousViewportSize: CGSize = .zero
        private var adjustingScroll = false
        private var defersFollowing: () -> Bool = { false }

        deinit { NotificationCenter.default.removeObserver(self) }

        func update(followsStreaming: Bool, requestID: UUID?, defersFollowing: @escaping () -> Bool) {
            self.defersFollowing = defersFollowing
            if self.followsStreaming && !followsStreaming { followFinalLayout = true }
            self.followsStreaming = followsStreaming
            if self.requestID != requestID {
                self.requestID = requestID
                followsBottom = true
                followFinalLayout = false
            }
            configureScroller()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); configureScroller() }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); configureScroller() }

        func configureScroller() {
            guard let scrollView = enclosingScrollView else { return }
            if observedScrollView !== scrollView {
                NotificationCenter.default.removeObserver(self)
                observedScrollView = scrollView
                if let document = scrollView.documentView {
                    previousHeight = document.frame.height
                    previousOrigin = scrollView.contentView.bounds.minY
                    previousViewportSize = scrollView.contentView.bounds.size
                    document.postsFrameChangedNotifications = true
                    scrollView.contentView.postsBoundsChangedNotifications = true
                    scrollView.contentView.postsFrameChangedNotifications = true
                    NotificationCenter.default.addObserver(self, selector: #selector(documentResized),
                        name: NSView.frameDidChangeNotification, object: document)
                    NotificationCenter.default.addObserver(self, selector: #selector(viewportScrolled),
                        name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
                    NotificationCenter.default.addObserver(self, selector: #selector(viewportResized),
                        name: NSView.frameDidChangeNotification, object: scrollView.contentView)
                }
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

        @objc private func viewportScrolled() {
            guard requestID != nil, !adjustingScroll, let scroll = observedScrollView,
                  let document = scroll.documentView else { return }
            // Layout can move the clip view before announcing a new document frame.
            // Only a scroll within the same geometry changes the user's follow intent.
            guard abs(document.frame.height - previousHeight) < 0.5,
                  scroll.contentView.bounds.size == previousViewportSize else { return }
            let bounds = scroll.contentView.bounds
            followsBottom = document.frame.height - bounds.maxY <= 24
            previousOrigin = bounds.minY
        }

        @objc private func documentResized() {
            guard requestID != nil, !adjustingScroll, let scroll = observedScrollView,
                  let document = scroll.documentView else { return }
            let height = document.frame.height
            guard abs(height - previousHeight) >= 0.5 else { return }
            previousHeight = height
            // The adaptive panel fits on a coalesced clock. Following now would
            // scroll the text up, then back down when the viewport catches up.
            synchronizeScroll(deferFollowing: defersFollowing())
        }

        @objc private func viewportResized() {
            guard let scroll = observedScrollView,
                  scroll.contentView.bounds.size != previousViewportSize else { return }
            previousViewportSize = scroll.contentView.bounds.size
            // Also handles the transition to the height cap: the remaining
            // overflow can now follow the bottom using the fitted viewport.
            synchronizeScroll(deferFollowing: false)
        }

        private func synchronizeScroll(deferFollowing: Bool) {
            guard requestID != nil, !adjustingScroll, let scroll = observedScrollView,
                  let document = scroll.documentView else { return }
            let bottom = max(0, document.frame.height - scroll.contentView.bounds.height)
            let follow = (followsStreaming || followFinalLayout) && followsBottom && !deferFollowing
            let target = follow ? bottom : min(previousOrigin, bottom)
            if !deferFollowing { followFinalLayout = false }
            adjustingScroll = true
            scroll.contentView.scroll(to: NSPoint(x: 0, y: target))
            scroll.reflectScrolledClipView(scroll.contentView)
            previousOrigin = target
            adjustingScroll = false
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
