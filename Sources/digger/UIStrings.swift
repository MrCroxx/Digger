import Foundation

enum AppLanguage: String, CaseIterable {
    case english = "en"
    case chineseSimplified = "zh-Hans"
    case japanese = "ja"

    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .chineseSimplified:
            return "简体中文"
        case .japanese:
            return "日本語"
        }
    }
}

enum TranslationTargetLanguage: String, CaseIterable {
    case english = "en"
    case chineseSimplified = "zh-Hans"
    case japanese = "ja"

    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .chineseSimplified:
            return "简体中文"
        case .japanese:
            return "日本語"
        }
    }

    var promptName: String {
        switch self {
        case .english:
            return "English"
        case .chineseSimplified:
            return "Simplified Chinese"
        case .japanese:
            return "Japanese"
        }
    }
}

enum UIStrings {
    enum Key: String {
        case translationEmptyResult
        case translationFailed
        case translationMissingApiKey
        case translationPrintPrefix
        case translationLoadingPrefix
        case popupOriginalTitle
        case popupTranslationTitle
        case preferencesTitle
        case preferencesDescription
        case preferencesPopupFontSizeLabel
        case preferencesLanguageLabel
        case preferencesTargetLanguageLabel
        case menuPreferences
        case menuQuit
        case menuEdit
        case menuUndo
        case menuRedo
        case menuCut
        case menuCopy
        case menuPaste
        case menuSelectAll
        case menuAppTitle
    }

    enum Translation {
        static var emptyResult: String { value(.translationEmptyResult) }
        static var failed: String { value(.translationFailed) }
        static var missingApiKey: String { value(.translationMissingApiKey) }
        static var printPrefix: String { value(.translationPrintPrefix) }
        static var loadingPrefix: String { value(.translationLoadingPrefix) }
    }

    enum Popup {
        static var originalTitle: String { value(.popupOriginalTitle) }
        static var translationTitle: String { value(.popupTranslationTitle) }
    }

    enum Preferences {
        static var title: String { value(.preferencesTitle) }
        static var description: String { value(.preferencesDescription) }
        static var popupFontSizeLabel: String { value(.preferencesPopupFontSizeLabel) }
        static var languageLabel: String { value(.preferencesLanguageLabel) }
        static var targetLanguageLabel: String { value(.preferencesTargetLanguageLabel) }
    }

    enum Menu {
        static var preferences: String { value(.menuPreferences) }
        static var quit: String { value(.menuQuit) }
        static var edit: String { value(.menuEdit) }
        static var undo: String { value(.menuUndo) }
        static var redo: String { value(.menuRedo) }
        static var cut: String { value(.menuCut) }
        static var copy: String { value(.menuCopy) }
        static var paste: String { value(.menuPaste) }
        static var selectAll: String { value(.menuSelectAll) }
        static var appTitle: String { value(.menuAppTitle) }
    }

    static func value(_ key: Key) -> String {
        let language = AppPreferences.language()
        if let localized = strings[language]?[key] {
            return localized
        }
        return strings[.english]?[key] ?? key.rawValue
    }

    private static let strings: [AppLanguage: [Key: String]] = [
        .english: [
            .translationEmptyResult: "Translation result is empty",
            .translationFailed: "Translation failed",
            .translationMissingApiKey: "OPENAI_API_KEY is not set",
            .translationPrintPrefix: "Translation:",
            .translationLoadingPrefix: "Translating",
            .popupOriginalTitle: "Original",
            .popupTranslationTitle: "Translation",
            .preferencesTitle: "Preferences",
            .preferencesDescription: "Settings are saved automatically.",
            .preferencesPopupFontSizeLabel: "Popup Font Size",
            .preferencesLanguageLabel: "Language",
            .preferencesTargetLanguageLabel: "Target Language",
            .menuPreferences: "Preferences…",
            .menuQuit: "Quit Digger",
            .menuEdit: "Edit",
            .menuUndo: "Undo",
            .menuRedo: "Redo",
            .menuCut: "Cut",
            .menuCopy: "Copy",
            .menuPaste: "Paste",
            .menuSelectAll: "Select All",
            .menuAppTitle: "Digger"
        ],
        .chineseSimplified: [
            .translationEmptyResult: "翻译结果为空",
            .translationFailed: "翻译失败",
            .translationMissingApiKey: "未检测到 OPENAI_API_KEY",
            .translationPrintPrefix: "译文:",
            .translationLoadingPrefix: "翻译中",
            .popupOriginalTitle: "原文",
            .popupTranslationTitle: "译文",
            .preferencesTitle: "偏好设置",
            .preferencesDescription: "设置会自动保存。",
            .preferencesPopupFontSizeLabel: "弹窗字号",
            .preferencesLanguageLabel: "语言",
            .preferencesTargetLanguageLabel: "目标语言",
            .menuPreferences: "偏好设置…",
            .menuQuit: "退出 Digger",
            .menuEdit: "编辑",
            .menuUndo: "撤销",
            .menuRedo: "重做",
            .menuCut: "剪切",
            .menuCopy: "复制",
            .menuPaste: "粘贴",
            .menuSelectAll: "全选",
            .menuAppTitle: "Digger"
        ],
        .japanese: [
            .translationEmptyResult: "翻訳結果が空です",
            .translationFailed: "翻訳に失敗しました",
            .translationMissingApiKey: "OPENAI_API_KEY が設定されていません",
            .translationPrintPrefix: "翻訳:",
            .translationLoadingPrefix: "翻訳中",
            .popupOriginalTitle: "原文",
            .popupTranslationTitle: "翻訳",
            .preferencesTitle: "環境設定",
            .preferencesDescription: "設定は自動的に保存されます。",
            .preferencesPopupFontSizeLabel: "ポップアップの文字サイズ",
            .preferencesLanguageLabel: "言語",
            .preferencesTargetLanguageLabel: "翻訳先",
            .menuPreferences: "環境設定…",
            .menuQuit: "Digger を終了",
            .menuEdit: "編集",
            .menuUndo: "取り消す",
            .menuRedo: "やり直す",
            .menuCut: "切り取り",
            .menuCopy: "コピー",
            .menuPaste: "貼り付け",
            .menuSelectAll: "すべて選択",
            .menuAppTitle: "Digger"
        ]
    ]
}
