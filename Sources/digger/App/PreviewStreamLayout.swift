#if DEBUG
import AppKit

/// Native-window regression checks; uses synthetic text and the preview preference suite.
@MainActor
enum PreviewStreamLayout {
    static let fixture = PreviewMode.markdownFixture + "\n\n" + """
    Keep the left edge steady while this paragraph wraps. 中英文混排也应保持阅读区宽度。

    | Field | Long value | Status |
    | --- | --- | --- |
    | key | \(String(repeating: "wide_value_", count: 10)) | Ready |

    ```swift
    let longLine = "\(String(repeating: "wide_code_", count: 12))"
    ```

    \(String(repeating: "More text to cross the vertical overflow boundary.\n\n", count: 3))
    """

    static func scrollViews(in view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }

    static func verify(_ window: NSWindow) {
        guard let root = window.contentView else { preconditionFailure("Missing popup content") }
        root.layoutSubtreeIfNeeded()
        guard let scroll = scrollViews(in: root).first, let document = scroll.documentView else {
            preconditionFailure("Missing reading scroll view")
        }
        assert(abs(scroll.frame.width - root.bounds.width) < 0.5, "Reading viewport changed width")
        assert(abs(scroll.contentView.bounds.width - root.bounds.width) < 0.5, "Scrollbar consumed reading width")
        assert(abs(document.frame.width - root.bounds.width) < 0.5, "Markdown expanded the reading width")
        assert(abs(document.frame.minX) < 0.5, "Markdown moved the reading area horizontally")
        assert(abs(scroll.contentView.bounds.minX) < 0.5, "Reading area scrolled horizontally")
        assert(scroll.scrollerStyle == .overlay, "Reading scrollbar lost overlay style")
    }

    static func verifyScrolling(_ window: NSWindow) {
        guard let root = window.contentView, let scroll = scrollViews(in: root).first,
              let document = scroll.documentView else { preconditionFailure("Missing scroll view") }
        assert(document.frame.height > scroll.contentView.bounds.height, "Fixture must overflow vertically")
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 40))
        scroll.reflectScrolledClipView(scroll.contentView)
        assert(scroll.contentView.bounds.minY > 0, "Vertical scrolling is broken")
        verify(window)
        let nested = document.subviews.flatMap { scrollViews(in: $0) }
        let wide = nested.filter { ($0.documentView?.frame.width ?? 0) > $0.contentView.bounds.width + 20 }
        // Code blocks now wrap by default; wide tables still scroll horizontally.
        assert(!wide.isEmpty, "Wide tables must retain horizontal scrolling")
        for inner in wide {
            assert(inner.scrollerStyle == .overlay)
            inner.contentView.scroll(to: NSPoint(x: 20, y: 0))
            inner.reflectScrolledClipView(inner.contentView)
            assert(inner.contentView.bounds.minX > 0, "Nested horizontal scrolling is broken")
        }
        verify(window)
    }

    static func verifyStreamInteraction(_ window: NSWindow, requestID: UUID, functionID: UUID) async {
        guard let root = window.contentView, let scroll = scrollViews(in: root).first,
              let document = scroll.documentView else { preconditionFailure("Missing scroll view") }
        func bottom() -> CGFloat { max(0, document.frame.height - scroll.contentView.bounds.height) }
        func move(to y: CGFloat) {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        func blockPositions(in view: NSView) -> [String: CGFloat] {
            var result: [String: CGFloat] = [:]
            if let id = view.identifier?.rawValue, id.hasPrefix("stream-block-") {
                result[id] = view.convert(view.bounds, to: document).minY
            }
            for child in view.subviews { result.merge(blockPositions(in: child)) { _, new in new } }
            return result
        }
        let positions = blockPositions(in: document)
        assert(positions.count >= 5, "Missing stable block geometry probes")
        move(to: bottom())
        var text = fixture
        for step in 0..<3 {
            if step == 1 { move(to: 40) }
            if step == 2 { move(to: bottom()) }
            text += "\n\n" + String(repeating: "A paced burst of new text. 中文连续输出。 ", count: 20)
            selectionPopup.model.receive(text, requestID: requestID, functionID: functionID, phase: .streaming)
            try? await Task.sleep(for: .milliseconds(900))
            verify(window)
            if step == 1 {
                assert(abs(scroll.contentView.bounds.minY - 40) < 1, "Stream stole the user's reading position")
            } else {
                assert(abs(scroll.contentView.bounds.minY - bottom()) < 1, "Stream stopped following the bottom")
            }
            let current = blockPositions(in: document)
            for (id, y) in positions {
                assert(abs((current[id] ?? -1000) - y) < 0.5, "An earlier Markdown block moved during streaming")
            }
        }
        selectionPopup.model.receive(text, requestID: requestID, functionID: functionID, phase: .complete)
        try? await Task.sleep(for: .milliseconds(150))
        assert(!selectionPopup.model.running)
    }
}
#endif
