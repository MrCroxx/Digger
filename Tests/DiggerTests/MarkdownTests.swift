import Foundation
import MarkdownUI
import Testing
@testable import digger

@MainActor
struct MarkdownTests {
    private let function = PopupFunction(id: UUID(), title: "Translation", prompt: "Translate", isTranslation: true)

    @Test func partialMarkdownRendersBeforeCompletionAndCopiesVerbatim() {
        let model = ResultModel(), id = UUID()
        model.begin(original: "# Original", requestID: id, functions: [function])
        var text = "## 标题\n\n**尚未闭合"
        model.update(text, requestID: id, functionID: function.id, phase: .streaming)
        #expect(model.running)
        #expect(model.sections[0].markdown.renderHTML().contains("<h2>标题</h2>"))
        #expect(model.sections[0].markdown.renderPlainText().contains("尚未闭合"))
        text += "**\n\n```swift\nlet value = \"**literal**\"\n"
        model.update(text, requestID: id, functionID: function.id, phase: .streaming)
        let html = model.sections[0].markdown.renderHTML()
        #expect(html.contains("<strong>尚未闭合</strong>"))
        #expect(html.contains("<pre><code class=\"language-swift\">"))
        #expect(!html.contains("<strong>literal</strong>"))
        model.stop()
        #expect(model.sections[0].text == text)
        #expect(model.combinedText(includeOriginal: true) == "# Original\n\nTranslation\n" + text)
    }

    @Test func tablesListsLinksAndLongFencesSurviveArbitraryChunkBoundaries() {
        let text = """
        # Features

        - **One**
          - Nested *two*
        - [x] Complete

        | Name | Status |
        | :--- | ---: |
        | `a\\|b` | ~~old~~ |

        > First
        >
        > Second [link](https://example.com/path?a=1)
        >
        > - Parent
        >   - Ordinary child
        >   - \\[x] Literal marker
        >   - [ ] Pending child

        ````markdown
        ```swift
        let x = "[x] literal"
        ```
        ````
        """
        let model = ResultModel(), id = UUID()
        model.begin(original: text, requestID: id, functions: [function])
        var accumulated = ""
        for character in text {
            accumulated.append(character)
            model.update(accumulated, requestID: id, functionID: function.id, phase: .streaming)
        }
        let html = model.sections[0].markdown.renderHTML()
        #expect(html.contains("<table>"))
        #expect(html.contains("<ul>"))
        #expect(html.contains("<del>old</del>"))
        #expect(html.components(separatedBy: "type=\"checkbox\"").count - 1 == 2, "\(html)")
        #expect(html.contains("href=\"https://example.com/path?a=1\""))
        #expect(html.contains("language-markdown"))
        #expect(html.contains("```swift"))
        #expect(model.sections[0].markdown.renderPlainText().contains("[x] literal"))
        #expect(model.sections[0].markdown.renderPlainText().contains("[x] Literal marker"))
        #expect(model.sections[0].text == text)
        #expect(model.originalMarkdown.renderHTML() == html)
    }
}
