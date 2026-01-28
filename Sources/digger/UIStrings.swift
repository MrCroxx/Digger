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
        case popupCopyTranslation
        case popupCopyResult
        case popupCopyAll
        case popupOpenPreferences
        case popupCopyTranslationSuccess
        case popupCopyResultSuccess
        case popupCopyAllSuccess
        case popupProcessingPrefix
        case popupEmptyResult
        case popupEmptyPrompt
        case popupUntitledFunction
        case preferencesTitle
        case preferencesDescription
        case preferencesPopupFontSizeLabel
        case preferencesPopupTooltipDelayLabel
        case preferencesPopupShortcutLabel
        case preferencesPopupShortcutPlaceholder
        case preferencesLanguageLabel
        case preferencesTargetLanguageLabel
        case preferencesStreamingLabel
        case preferencesCustomFunctionsTitle
        case preferencesCustomFunctionsDescription
        case preferencesFunctionTitleLabel
        case preferencesFunctionPromptLabel
        case preferencesAddFunction
        case preferencesRemoveFunction
        case preferencesFunctionTitlePlaceholder
        case preferencesFunctionPromptPlaceholder
        case preferencesFunctionDefaultTitle
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
        static var copyTranslation: String { value(.popupCopyTranslation) }
        static var copyResult: String { value(.popupCopyResult) }
        static var copyAll: String { value(.popupCopyAll) }
        static var openPreferences: String { value(.popupOpenPreferences) }
        static var copyTranslationSuccess: String { value(.popupCopyTranslationSuccess) }
        static var copyResultSuccess: String { value(.popupCopyResultSuccess) }
        static var copyAllSuccess: String { value(.popupCopyAllSuccess) }
        static var processingPrefix: String { value(.popupProcessingPrefix) }
        static var emptyResult: String { value(.popupEmptyResult) }
        static var emptyPrompt: String { value(.popupEmptyPrompt) }
        static var untitledFunction: String { value(.popupUntitledFunction) }
    }

    enum Preferences {
        static var title: String { value(.preferencesTitle) }
        static var description: String { value(.preferencesDescription) }
        static var popupFontSizeLabel: String { value(.preferencesPopupFontSizeLabel) }
        static var popupTooltipDelayLabel: String { value(.preferencesPopupTooltipDelayLabel) }
        static var popupShortcutLabel: String { value(.preferencesPopupShortcutLabel) }
        static var popupShortcutPlaceholder: String { value(.preferencesPopupShortcutPlaceholder) }
        static var languageLabel: String { value(.preferencesLanguageLabel) }
        static var targetLanguageLabel: String { value(.preferencesTargetLanguageLabel) }
        static var streamingLabel: String { value(.preferencesStreamingLabel) }
        static var customFunctionsTitle: String { value(.preferencesCustomFunctionsTitle) }
        static var customFunctionsDescription: String { value(.preferencesCustomFunctionsDescription) }
        static var functionTitleLabel: String { value(.preferencesFunctionTitleLabel) }
        static var functionPromptLabel: String { value(.preferencesFunctionPromptLabel) }
        static var addFunction: String { value(.preferencesAddFunction) }
        static var removeFunction: String { value(.preferencesRemoveFunction) }
        static var functionTitlePlaceholder: String { value(.preferencesFunctionTitlePlaceholder) }
        static var functionPromptPlaceholder: String { value(.preferencesFunctionPromptPlaceholder) }
        static var functionDefaultTitle: String { value(.preferencesFunctionDefaultTitle) }
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
            .popupCopyTranslation: "Copy Translation",
            .popupCopyResult: "Copy Result",
            .popupCopyAll: "Copy All Results",
            .popupOpenPreferences: "Open Preferences",
            .popupCopyTranslationSuccess: "Translation copied",
            .popupCopyResultSuccess: "Result copied",
            .popupCopyAllSuccess: "All results copied",
            .popupProcessingPrefix: "Processing",
            .popupEmptyResult: "Result is empty",
            .popupEmptyPrompt: "Prompt is empty",
            .popupUntitledFunction: "Untitled Function",
            .preferencesTitle: "Preferences",
            .preferencesDescription: "Settings are saved automatically.",
            .preferencesPopupFontSizeLabel: "Popup Font Size",
            .preferencesPopupTooltipDelayLabel: "Popup Tooltip Delay (ms)",
            .preferencesPopupShortcutLabel: "Trigger Shortcut",
            .preferencesPopupShortcutPlaceholder: "Press shortcut",
            .preferencesLanguageLabel: "Language",
            .preferencesTargetLanguageLabel: "Target Language",
            .preferencesStreamingLabel: "Stream Translation",
            .preferencesCustomFunctionsTitle: "Custom Functions",
            .preferencesCustomFunctionsDescription: "Add prompts that apply to selected text.",
            .preferencesFunctionTitleLabel: "Title",
            .preferencesFunctionPromptLabel: "Prompt",
            .preferencesAddFunction: "Add Function",
            .preferencesRemoveFunction: "Remove",
            .preferencesFunctionTitlePlaceholder: "Function title",
            .preferencesFunctionPromptPlaceholder: "Enter prompt",
            .preferencesFunctionDefaultTitle: "New Function",
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
            .popupCopyTranslation: "复制译文",
            .popupCopyResult: "复制结果",
            .popupCopyAll: "复制所有结果",
            .popupOpenPreferences: "打开偏好设置",
            .popupCopyTranslationSuccess: "译文已复制",
            .popupCopyResultSuccess: "结果已复制",
            .popupCopyAllSuccess: "结果已复制",
            .popupProcessingPrefix: "处理中",
            .popupEmptyResult: "结果为空",
            .popupEmptyPrompt: "提示语为空",
            .popupUntitledFunction: "未命名功能",
            .preferencesTitle: "偏好设置",
            .preferencesDescription: "设置会自动保存。",
            .preferencesPopupFontSizeLabel: "弹窗字号",
            .preferencesPopupTooltipDelayLabel: "弹窗提示延迟 (毫秒)",
            .preferencesPopupShortcutLabel: "触发快捷键",
            .preferencesPopupShortcutPlaceholder: "按下快捷键",
            .preferencesLanguageLabel: "语言",
            .preferencesTargetLanguageLabel: "目标语言",
            .preferencesStreamingLabel: "流式译文",
            .preferencesCustomFunctionsTitle: "自定义功能",
            .preferencesCustomFunctionsDescription: "添加应用于选中文本的提示语。",
            .preferencesFunctionTitleLabel: "标题",
            .preferencesFunctionPromptLabel: "Prompt",
            .preferencesAddFunction: "添加功能",
            .preferencesRemoveFunction: "删除",
            .preferencesFunctionTitlePlaceholder: "功能标题",
            .preferencesFunctionPromptPlaceholder: "输入 prompt",
            .preferencesFunctionDefaultTitle: "新功能",
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
            .popupCopyTranslation: "翻訳をコピー",
            .popupCopyResult: "結果をコピー",
            .popupCopyAll: "すべての結果をコピー",
            .popupOpenPreferences: "環境設定を開く",
            .popupCopyTranslationSuccess: "翻訳をコピーしました",
            .popupCopyResultSuccess: "結果をコピーしました",
            .popupCopyAllSuccess: "結果をコピーしました",
            .popupProcessingPrefix: "処理中",
            .popupEmptyResult: "結果が空です",
            .popupEmptyPrompt: "プロンプトが空です",
            .popupUntitledFunction: "無題の機能",
            .preferencesTitle: "環境設定",
            .preferencesDescription: "設定は自動的に保存されます。",
            .preferencesPopupFontSizeLabel: "ポップアップの文字サイズ",
            .preferencesPopupTooltipDelayLabel: "ポップアップのツールチップ遅延 (ミリ秒)",
            .preferencesPopupShortcutLabel: "トリガーショートカット",
            .preferencesPopupShortcutPlaceholder: "ショートカットを入力",
            .preferencesLanguageLabel: "言語",
            .preferencesTargetLanguageLabel: "翻訳先",
            .preferencesStreamingLabel: "ストリーミング翻訳",
            .preferencesCustomFunctionsTitle: "カスタム機能",
            .preferencesCustomFunctionsDescription: "選択したテキストに適用するプロンプトを追加します。",
            .preferencesFunctionTitleLabel: "タイトル",
            .preferencesFunctionPromptLabel: "プロンプト",
            .preferencesAddFunction: "機能を追加",
            .preferencesRemoveFunction: "削除",
            .preferencesFunctionTitlePlaceholder: "機能タイトル",
            .preferencesFunctionPromptPlaceholder: "プロンプトを入力",
            .preferencesFunctionDefaultTitle: "新規機能",
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
