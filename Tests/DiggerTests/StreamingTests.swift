import Foundation
import Testing
@testable import digger

@MainActor
struct StreamingTests {
    private let function = PopupFunction(id: UUID(), title: "Translate", prompt: "Translate", isTranslation: true)

    @Test func burstIsPacedAndDrainsWithoutAnotherNetworkEvent() {
        var buffer = StreamingText()
        let text = String(repeating: "中文 👨‍👩‍👧‍👦 e\u{301} smooth streaming. ", count: 30)
        buffer.receive(text)
        let first = buffer.advance()
        #expect(!first.isEmpty && first.count < text.count)
        #expect(text.hasPrefix(first))
        var previous = first
        for _ in 0..<40 {
            let next = buffer.advance()
            #expect(next.hasPrefix(previous))
            #expect(text.hasPrefix(next))
            previous = next
        }
        #expect(buffer.isCaughtUp)
        #expect(buffer.visible == text)
        buffer.receive("replacement")
        for _ in 0..<10 { _ = buffer.advance() }
        #expect(buffer.visible == "replacement")
    }

    @Test func pendingMarkdownIsOptimisticAndCodeRemainsLiteral() {
        let cases: [(String, String)] = [
            ("**尚未闭合", "<strong>尚未闭合</strong>"),
            ("*斜体", "<em>斜体</em>"),
            ("~~删除", "<del>删除</del>"),
            ("`let x", "<code>let x</code>"),
            ("**粗体*", "<strong>粗体</strong>"),
            ("[链接](https://exam", "<p>链接</p>"),
            ("[链接", "<p>链接</p>"),
            ("**粗体和 *斜体", "<strong>粗体和 <em>斜体</em></strong>"),
            ("```swift\nlet x = \"**literal\"", "**literal"),
            ("    **literal", "**literal"),
            ("a_b_c", "a_b_c"),
            (#"\*literal"#, "*literal")
        ]
        for (source, expected) in cases {
            let rendered = PopupMarkdown.parse(StreamingMarkdown.displaySource(source)).renderHTML()
            #expect(rendered.contains(expected), "Source: \(source), rendered: \(rendered)")
        }
    }

    @Test func combiningMarkAcrossNetworkChunksDoesNotReplayTheAnswer() {
        var buffer = StreamingText()
        let prefix = String(repeating: "Already read. ", count: 20)
        buffer.receive(prefix + "e")
        for _ in 0..<40 { _ = buffer.advance() }
        buffer.receive(prefix + "e\u{301}")
        #expect(buffer.visible == prefix)
        #expect(buffer.advance() == prefix + "e\u{301}")
    }

    @Test func tableHeaderDoesNotFlashAsPipeTextWhileDelimiterArrives() {
        for tail in ["| Name | Value", "| Name | Value |\n", "| Name | Value |\n| -", "| Name | Value |\n| --- | --"] {
            #expect(StreamingMarkdown.displaySource("Intro.\n\n" + tail).trimmingCharacters(in: .whitespacesAndNewlines) == "Intro.")
        }
        let source = "Intro.\n\n| Name | Value |\n| --- | --- |"
        #expect(PopupMarkdown.parse(StreamingMarkdown.displaySource(source)).renderHTML().contains("<table>"))
    }

    @Test func unchangedBlocksKeepParsedIdentityAndReferencesCanResolveLater() {
        let first = PopupMarkdown.blocks("# Title\n\nFinished paragraph.\n\n**Tail")
        let next = PopupMarkdown.blocks("# Title\n\nFinished paragraph.\n\n**Tail grows**", reusing: first)
        #expect(first.count == 3 && next.count == 3)
        #expect(first[0].revision == next[0].revision)
        #expect(first[1].revision == next[1].revision)
        #expect(first[2].id == next[2].id)
        #expect(first[2].revision != next[2].revision)
        let unresolved = PopupMarkdown.blocks("[reference][target]\n\nTail")
        let resolved = PopupMarkdown.blocks("[reference][target]\n\nTail\n\n[target]: https://example.com", reusing: unresolved)
        #expect(resolved[0].content.renderHTML().contains("href=\"https://example.com\""))
        #expect(unresolved[0].revision != resolved[0].revision)
    }

    @Test func completionDrainsThenRestoresExactMarkdownWithoutChangingCopy() {
        let model = ResultModel(), id = UUID()
        model.begin(original: "source", requestID: id, functions: [function])
        let text = "**" + String(repeating: "unfinished ", count: 30)
        model.receive(text, requestID: id, functionID: function.id, phase: .streaming)
        model.advanceStream()
        #expect(model.sections[0].text == text)
        #expect(model.sections[0].markdown.renderHTML().contains("<strong>"))
        #expect(model.sections[0].markdown.renderPlainText().count < text.count)
        model.receive(text, requestID: id, functionID: function.id, phase: .complete)
        #expect(model.running)
        for _ in 0..<40 { model.advanceStream() }
        #expect(!model.running)
        #expect(model.sections[0].markdown.renderHTML() == PopupMarkdown.parse(text).renderHTML())
        #expect(model.combinedText(includeOriginal: false) == "Translate\n" + text)
    }

    @Test func stopFlushesReceivedTextAndNewRequestDropsBufferedOldFrames() {
        let model = ResultModel(), old = UUID(), current = UUID()
        model.begin(original: "old", requestID: old, functions: [function])
        let text = String(repeating: "**partial** ", count: 20)
        model.receive(text, requestID: old, functionID: function.id, phase: .streaming)
        model.advanceStream()
        model.stop()
        #expect(model.sections[0].text == text)
        #expect(model.sections[0].markdown.renderHTML() == PopupMarkdown.parse(text).renderHTML())
        model.advanceStream()
        #expect(model.sections[0].phase == .stopped)
        model.begin(original: "new", requestID: current, functions: [function])
        model.receive("stale", requestID: old, functionID: function.id, phase: .complete)
        model.advanceStream()
        #expect(model.sections[0].text.isEmpty)
        model.receive("cached", requestID: current, functionID: function.id, phase: .complete, cached: true)
        #expect(model.sections[0].markdown.renderPlainText() == "cached")
        #expect(!model.running)
    }

    @Test func firstFragmentAppearsEvenIfTheNetworkPauses() async throws {
        let model = ResultModel(), id = UUID()
        model.begin(original: "source", requestID: id, functions: [function])
        model.receive("Hello 世界", requestID: id, functionID: function.id, phase: .streaming)
        // Other native tests share the main actor. Wait for the actual presentation
        // condition with a deadline rather than assuming two scheduled frames ran.
        let deadline = ContinuousClock.now + .seconds(2)
        while model.sections[0].markdown.renderPlainText() != "Hello 世界", ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.sections[0].markdown.renderPlainText() == "Hello 世界")
        #expect(model.running)
        model.stop()
    }

    @Test func simultaneousActionsDrainIndependentlyAndFailureClearsItsBuffer() {
        let model = ResultModel(), id = UUID()
        let summary = PopupFunction(id: UUID(), title: "Summary", prompt: "Summarize", isTranslation: false)
        model.begin(original: "source", requestID: id, functions: [function, summary])
        model.receive(String(repeating: "translation ", count: 100), requestID: id, functionID: function.id, phase: .streaming)
        model.receive("summary", requestID: id, functionID: summary.id, phase: .streaming)
        model.receive("summary", requestID: id, functionID: summary.id, phase: .complete)
        for _ in 0..<5 { model.advanceStream() }
        #expect(model.sections[1].phase == .complete)
        #expect(model.sections[0].phase == .streaming)
        model.receive("error", requestID: id, functionID: function.id, phase: .failed)
        for _ in 0..<40 { model.advanceStream() }
        #expect(model.sections[0].markdown.renderPlainText() == "error")
        #expect(!model.running)
    }
}
