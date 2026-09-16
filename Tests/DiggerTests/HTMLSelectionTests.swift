import AppKit
import Foundation
import Testing
@testable import digger

@MainActor
struct HTMLSelectionTests {
    @Test func webpageTOCKeepsHierarchyLinksAndCode() throws {
        let file = try #require(Bundle.module.url(forResource: "toc", withExtension: "html", subdirectory: "Fixtures"))
        let markdown = try #require(HTMLSelectionMarkdown.convert(String(contentsOf: file, encoding: .utf8)))
        #expect(markdown.contains("\n  - [2\\.1 Ruling Out the Impact of `iou-wrk`](<#iou-wrk>)"))
        #expect(!markdown.contains("Table of contents"))
        #expect(!markdown.contains("Unselected footer"))
        let html = PopupMarkdown.parse(markdown).renderHTML()
        #expect(html.components(separatedBy: "<li>").count - 1 == 8)
        #expect(html.components(separatedBy: "<ul>").count - 1 == 2)
        #expect(html.contains("<code>iou-wrk</code>"))
        #expect(html.contains("href=\"#scale\""))
        #expect(html.contains("0. “Task Failed Successfully”"))
        #expect(html.contains("X. “A Planet Upside Down”"))
    }

    @Test func browserRichSelectionWinsOverFlattenedAccessibilityText() throws {
        let file = try #require(Bundle.module.url(forResource: "toc", withExtension: "html", subdirectory: "Fixtures"))
        let rich = HTMLSelectionMarkdown.convert(try String(contentsOf: file, encoding: .utf8))
        let selected = SelectionHandler.readSelection(isWeb: true, accessibilityText: "0. Task · 1. Demo · 2. Scale",
                                                      copy: { rich }, word: { "caret word" })
        #expect(selected == rich)
        #expect(SelectionHandler.readSelection(isWeb: true, accessibilityText: "AX fallback", copy: { nil }, word: { nil }) == "AX fallback")
        var copied = false
        let rawMarkdown = "    code\n\n# Heading\n"
        let editor = SelectionHandler.readSelection(isWeb: false, accessibilityText: rawMarkdown,
                                                     copy: { copied = true; return rich }, word: { nil })
        #expect(editor == rawMarkdown)
        #expect(!copied)
    }

    @Test func partialFragmentKeepsOnlySelectionAndItsAncestors() throws {
        let source = "<h1>Not selected</h1><ol start='3'><li>Before</li><li><a href='#b'>Unselected prefix<!--StartFragment-->Chosen <code>value</code></a></li><li>Next<!--EndFragment-->Unselected suffix</li><li>After</li></ol>"
        let markdown = try #require(HTMLSelectionMarkdown.convert(source))
        #expect(markdown.hasPrefix("4. [Chosen `value`](<#b>)"))
        #expect(markdown.contains("\n5. Next"))
        #expect(!markdown.contains("Unselected"))
        #expect(!markdown.contains("Before"))
        #expect(!markdown.contains("After"))
    }

    @Test func headingsQuotesTablesAndCodeBecomeMarkdown() throws {
        let source = "<h2>A &amp; B</h2><p><strong>Bold</strong> <em>emphasis</em><br>next</p><blockquote>Quote</blockquote><table><tr><th>Name</th><th>Value</th></tr><tr><td>x</td><td>a|b</td></tr></table><pre><code class='language-swift'>  let x = &quot;```&quot;\n</code></pre><script>not selected text</script><style>ignore me</style>"
        let markdown = try #require(HTMLSelectionMarkdown.convert(source))
        #expect(markdown.contains("## A & B"))
        #expect(markdown.contains("**Bold** *emphasis*  \nnext"))
        #expect(markdown.contains("> Quote"))
        #expect(markdown.contains("| x | a\\|b |"))
        #expect(markdown.contains("````swift\n  let x = \"```\"\n````"))
        #expect(!markdown.contains("not selected text"))
        #expect(!markdown.contains("ignore me"))
    }

    @Test func literalMarkdownInHTMLTextDoesNotInventFormatting() throws {
        let markdown = try #require(HTMLSelectionMarkdown.convert("<p>*literal* [brackets] &lt;tag&gt;</p><a href='javascript:alert(1)'>label</a>"))
        let html = PopupMarkdown.parse(markdown).renderHTML()
        #expect(!html.contains("<em>"))
        #expect(!html.contains("javascript:"))
        #expect(PopupMarkdown.parse(markdown).renderPlainText().contains("*literal* [brackets] <tag>"))
    }

    @Test func webArchiveClipboardPreservesRichSelectionWhenHTMLFlavorIsMissing() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let html = "<ul><li>Parent<ul><li><code>iou-wrk</code></li></ul></li></ul>"
        let archive: [String: Any] = ["WebMainResource": ["WebResourceMIMEType": "text/html",
            "WebResourceTextEncodingName": "UTF-8", "WebResourceData": Data(html.utf8)]]
        board.setString("Parent · iou-wrk", forType: .string)
        board.setData(try PropertyListSerialization.data(fromPropertyList: archive, format: .binary, options: 0),
                      forType: .init("Apple Web Archive pasteboard type"))
        let content = SelectionClipboardContent(pasteboard: board)
        #expect(content.html == html)
        #expect(content.plainText == "Parent · iou-wrk")
        #expect(HTMLSelectionMarkdown.convert(try #require(content.html)) == "- Parent\n  - `iou-wrk`")
        board.setString("<p>Direct HTML</p>", forType: .html)
        #expect(SelectionClipboardContent(pasteboard: board).html == "<p>Direct HTML</p>")
    }

    @Test func clipboardSnapshotRestoresEveryFlavorWithoutOverwritingNewCopy() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("original", forType: .string)
        board.setString("<b>original</b>", forType: .html)
        let snapshot = PasteboardSnapshot(pasteboard: board)
        board.clearContents()
        board.setString("temporary selection", forType: .string)
        let count = board.changeCount
        snapshot.restore(to: board, ifUnchangedSince: count)
        #expect(board.string(forType: .string) == "original")
        #expect(board.string(forType: .html) == "<b>original</b>")
        let oldCount = board.changeCount
        board.clearContents()
        board.setString("new user copy", forType: .string)
        snapshot.restore(to: board, ifUnchangedSince: oldCount)
        #expect(board.string(forType: .string) == "new user copy")
    }
}
