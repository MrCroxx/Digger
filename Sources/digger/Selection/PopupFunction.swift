import Foundation

struct PopupFunction: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let prompt: String
    let isTranslation: Bool

    static func availableFunctions() -> [PopupFunction] {
        AppPreferences.customFunctions().map { custom in
            let trimmedTitle = custom.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = trimmedTitle.isEmpty ? UIStrings.Popup.untitledFunction : trimmedTitle
            return PopupFunction(id: custom.id, title: title, prompt: custom.prompt, isTranslation: false)
        }
    }
}
