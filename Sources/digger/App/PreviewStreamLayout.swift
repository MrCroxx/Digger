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
        assert(wide.count >= 2, "Wide table and code must retain horizontal scrolling")
        for inner in wide {
            assert(inner.scrollerStyle == .overlay)
            inner.contentView.scroll(to: NSPoint(x: 20, y: 0))
            inner.reflectScrolledClipView(inner.contentView)
            assert(inner.contentView.bounds.minX > 0, "Nested horizontal scrolling is broken")
        }
        verify(window)
    }
}
#endif
