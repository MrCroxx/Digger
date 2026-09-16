import Foundation

struct CustomFunction: Codable, Equatable, Identifiable {
    static let defaultSummaryID = UUID(uuidString: "70E04CD5-D763-4401-906B-72793E91E102")!
    static let defaultSummaryPrompt = "Summarize it in one sentence."

    let id: UUID
    var title: String
    var prompt: String
    var isEnabled: Bool

    init(id: UUID = UUID(), title: String, prompt: String, isEnabled: Bool = true) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, prompt, isEnabled
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        prompt = try values.decode(String.self, forKey: .prompt)
        // Older releases also saved built-ins with random IDs. Only migrate the
        // known Summary default; preserve custom actions and explicit choices.
        let isDefaultSummary = id == Self.defaultSummaryID ||
            (title == "Summary" && prompt == Self.defaultSummaryPrompt)
        isEnabled = try values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? !isDefaultSummary
    }
}
