import Foundation

struct PromptLayout: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var prompt: String

    init(id: UUID = UUID(), title: String, prompt: String) {
        self.id = id
        self.title = title
        self.prompt = prompt
    }
}

enum PromptLayoutPreferences {
    private static let layoutsKey = "PromptLayouts"
    private static let translationLayoutEnabledKey = "TranslationLayoutEnabled"
    private static let defaultTranslationLayoutEnabled = true

    static func loadLayouts() -> [PromptLayout] {
        guard let data = UserDefaults.standard.data(forKey: layoutsKey) else {
            return []
        }
        do {
            return try JSONDecoder().decode([PromptLayout].self, from: data)
        } catch {
            return []
        }
    }

    static func saveLayouts(_ layouts: [PromptLayout]) {
        do {
            let data = try JSONEncoder().encode(layouts)
            UserDefaults.standard.set(data, forKey: layoutsKey)
        } catch {
            return
        }
    }

    static func translationLayoutEnabled() -> Bool {
        if UserDefaults.standard.object(forKey: translationLayoutEnabledKey) == nil {
            return defaultTranslationLayoutEnabled
        }
        return UserDefaults.standard.bool(forKey: translationLayoutEnabledKey)
    }

    static func setTranslationLayoutEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: translationLayoutEnabledKey)
    }
}
