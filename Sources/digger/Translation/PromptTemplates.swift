import Foundation

enum PromptTemplates {
    static func translation(for targetLanguage: TranslationTargetLanguage) -> String {
        "Translate the user's text into \(targetLanguage.promptName). Preserve meaning, formatting, and proper nouns."
    }
}
