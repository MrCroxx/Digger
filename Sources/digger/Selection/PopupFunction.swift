import Foundation

struct PopupFunction: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let prompt: String
    let isTranslation: Bool

    static let translationID = UUID(uuidString: "0DFA4B4E-0A6C-4B63-9D1B-3DDAE32F8F0A")!

    static func translationFunction() -> PopupFunction {
        PopupFunction(
            id: translationID,
            title: UIStrings.Popup.translationTitle,
            prompt: PromptTemplates.translation(for: AppPreferences.translationTargetLanguage()),
            isTranslation: true
        )
    }

    static func availableFunctions() -> [PopupFunction] {
        let translation = PopupFunction.translationFunction()
        let customFunctions = AppPreferences.customFunctions().map { custom in
            let trimmedTitle = custom.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = trimmedTitle.isEmpty ? UIStrings.Popup.untitledFunction : trimmedTitle
            return PopupFunction(id: custom.id, title: title, prompt: custom.prompt, isTranslation: false)
        }
        return [translation] + customFunctions
    }
}
