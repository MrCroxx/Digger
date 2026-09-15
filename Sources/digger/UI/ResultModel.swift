import Foundation
import MarkdownUI

@MainActor
final class ResultModel: ObservableObject {
    enum Phase: Equatable { case waiting, streaming, complete, failed, stopped }
    struct Section: Identifiable {
        let id: UUID
        let title: String
        var text = ""
        var markdown = MarkdownUI.MarkdownContent("")
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
    var running: Bool { sections.contains { $0.phase == .waiting || $0.phase == .streaming } }
    var completedCount: Int { sections.filter { $0.phase == .complete }.count }

    func begin(original: String, requestID: UUID, functions: [PopupFunction]) {
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
        if sections[index].text != text {
            sections[index].markdown = PopupMarkdown.parse(text)
            sections[index].text = text
        }
        sections[index].phase = phase
        sections[index].cached = cached
    }

    func stop() {
        for index in sections.indices where sections[index].phase == .waiting || sections[index].phase == .streaming {
            sections[index].phase = .stopped
        }
    }

    func combinedText(includeOriginal: Bool) -> String {
        let results = sections.filter { !$0.text.isEmpty }.map { "\($0.title)\n\($0.text)" }
        return ((includeOriginal ? [original] : []) + results).joined(separator: "\n\n")
    }
}
