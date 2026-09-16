import Foundation
import MarkdownUI

@MainActor
final class ResultModel: ObservableObject {
    enum Phase: Equatable { case waiting, streaming, complete, failed, stopped }
    struct Section: Identifiable {
        let id: UUID
        let title: String
        var text = ""
        var blocks: [PopupMarkdown.Block] = []
        var markdown: MarkdownUI.MarkdownContent {
            MarkdownUI.MarkdownContent { for block in blocks { block.content } }
        }
        var phase: Phase = .waiting
        var cached = false
        var collapsed = false
    }
    struct Notice {
        let title: String
        let message: String
        let needsAccessibility: Bool
    }
    @Published var notice: Notice?
    @Published var requestID: UUID?
    @Published var original = ""
    private(set) var originalMarkdown = MarkdownUI.MarkdownContent("")
    @Published var sections: [Section] = []
    @Published var originalCollapsed = AppPreferences.popupOriginalCollapsed()
    @Published var pinned = false
    @Published var fontSize = PopupFontPreferences.load()
    @Published var opacity = AppPreferences.popupOpacity()
    @Published var language = AppPreferences.language()
    @Published var copied = false
    private struct Pending {
        var reveal = StreamingText()
        var phase: Phase = .streaming
        var cached = false
    }
    private var pending: [UUID: Pending] = [:]
    private var revealTask: Task<Void, Never>?
    var running: Bool { sections.contains { $0.phase == .waiting || $0.phase == .streaming } }
    var completedCount: Int { sections.filter { $0.phase == .complete }.count }

    func begin(original: String, requestID: UUID, functions: [PopupFunction]) {
        revealTask?.cancel()
        revealTask = nil
        pending.removeAll()
        notice = nil
        self.requestID = requestID
        self.originalMarkdown = PopupMarkdown.parse(original)
        self.original = original
        copied = false
        let collapsed = AppPreferences.popupCollapsedFunctionIDs()
        sections = functions.map { Section(id: $0.id, title: $0.title, collapsed: collapsed.contains($0.id)) }
    }

    func update(_ text: String, requestID: UUID, functionID: UUID,
                phase: Phase, cached: Bool = false) {
        guard self.requestID == requestID,
              let index = sections.firstIndex(where: { $0.id == functionID }),
              sections[index].phase != .stopped else { return }
        pending.removeValue(forKey: functionID)
        var section = sections[index]
        section.blocks = PopupMarkdown.blocks(phase == .streaming ? StreamingMarkdown.displaySource(text) : text,
                                             reusing: section.blocks)
        section.text = text
        section.phase = phase
        section.cached = cached
        sections[index] = section
    }

    /// Receive immediately for copying; publish display snapshots on one shared clock.
    func receive(_ text: String, requestID: UUID, functionID: UUID, phase: Phase, cached: Bool = false) {
        guard self.requestID == requestID,
              let index = sections.firstIndex(where: { $0.id == functionID }),
              sections[index].phase != .stopped else { return }
        if cached || phase == .failed || (phase == .complete && pending[functionID] == nil) {
            update(text, requestID: requestID, functionID: functionID, phase: phase, cached: cached)
            return
        }
        var value = pending[functionID] ?? Pending()
        value.reveal.receive(text)
        value.phase = phase
        value.cached = cached
        pending[functionID] = value
        var section = sections[index]
        section.text = text
        section.phase = .streaming
        sections[index] = section
        guard revealTask == nil else { return }
        revealTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard !Task.isCancelled, let self else { return }
                self.advanceStream()
                if self.pending.values.allSatisfy({ $0.reveal.isCaughtUp }) { self.revealTask = nil; return }
            }
        }
    }

    /// Also used by deterministic regression tests, without sleeping or API calls.
    func advanceStream() {
        var next = sections
        var changed = false
        for index in next.indices {
            let id = next[index].id
            guard var value = pending[id] else { continue }
            let previous = value.reveal.visible
            let visible = value.reveal.advance()
            let finished = value.phase == .complete && value.reveal.isCaughtUp
            guard visible != previous || finished else { continue }
            let source = finished ? visible : StreamingMarkdown.displaySource(visible)
            let blocks = PopupMarkdown.blocks(source, reusing: next[index].blocks)
            if blocks != next[index].blocks || finished {
                next[index].blocks = blocks
                next[index].phase = finished ? .complete : .streaming
                next[index].cached = value.cached
                changed = true
            }
            if finished { pending.removeValue(forKey: id) }
            else { pending[id] = value }
        }
        if changed { sections = next }
    }

    func stop() {
        revealTask?.cancel()
        revealTask = nil
        pending.removeAll()
        for index in sections.indices where sections[index].phase == .waiting || sections[index].phase == .streaming {
            sections[index].blocks = PopupMarkdown.blocks(sections[index].text, reusing: sections[index].blocks)
            sections[index].phase = .stopped
        }
    }

    func combinedText(includeOriginal: Bool) -> String {
        let results = sections.filter { !$0.text.isEmpty }.map { "\($0.title)\n\($0.text)" }
        return ((includeOriginal ? [original] : []) + results).joined(separator: "\n\n")
    }
}
