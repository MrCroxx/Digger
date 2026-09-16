import Foundation

struct PopupFunction: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let prompt: String
    let isTranslation: Bool

    static func availableFunctions(from functions: [CustomFunction] = AppPreferences.customFunctions()) -> [PopupFunction] {
        functions.filter(\.isEnabled).map { custom in
            let trimmedTitle = custom.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = trimmedTitle.isEmpty ? UIStrings.Popup.untitledFunction : trimmedTitle
            return PopupFunction(id: custom.id, title: title, prompt: custom.prompt, isTranslation: false)
        }
    }
}
