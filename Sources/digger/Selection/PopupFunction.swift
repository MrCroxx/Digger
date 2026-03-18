import Foundation

struct PopupFunction: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let prompt: String
    let isSystemDictionary: Bool

    private static let systemDictionaryID = UUID(uuidString: "0F3276C3-1A3D-4A6A-9C6F-A4B6E66B343E")!

    static func availableFunctions() -> [PopupFunction] {
        var functions: [PopupFunction] = []
        if AppPreferences.systemDictionaryEnabled() {
            functions.append(
                PopupFunction(
                    id: systemDictionaryID,
                    title: UIStrings.Popup.dictionaryTitle,
                    prompt: "",
                    isSystemDictionary: true
                )
            )
        }
        functions.append(contentsOf: AppPreferences.customFunctions().map { custom in
            let trimmedTitle = custom.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = trimmedTitle.isEmpty ? UIStrings.Popup.untitledFunction : trimmedTitle
            return PopupFunction(id: custom.id, title: title, prompt: custom.prompt, isSystemDictionary: false)
        })
        return functions
    }
}
