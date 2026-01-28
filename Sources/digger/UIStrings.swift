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
        case layoutEmptyResult
        case layoutFailed
        case layoutLoadingPrefix
        case popupOriginalTitle
        case popupTranslationTitle
        case popupCopyTranslation
        case popupCopyAll
        case popupOpenPreferences
        case preferencesTitle
        case preferencesDescription
        case preferencesPopupFontSizeLabel
        case preferencesPopupTooltipDelayLabel
        case preferencesLanguageLabel
        case preferencesTargetLanguageLabel
        case preferencesStreamingLabel
        case preferencesLayoutsTitle
        case preferencesLayoutTitleLabel
        case preferencesLayoutPromptLabel
        case preferencesAddLayout
        case preferencesRemoveLayout
        case preferencesTranslationLayoutToggle
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

    enum Layout {
        static var emptyResult: String { value(.layoutEmptyResult) }
        static var failed: String { value(.layoutFailed) }
        static var loadingPrefix: String { value(.layoutLoadingPrefix) }
    }

    enum Popup {
        static var originalTitle: String { value(.popupOriginalTitle) }
        static var translationTitle: String { value(.popupTranslationTitle) }
        static var copyTranslation: String { value(.popupCopyTranslation) }
        static var copyAll: String { value(.popupCopyAll) }
        static var openPreferences: String { value(.popupOpenPreferences) }
    }

    enum Preferences {
        static var title: String { value(.preferencesTitle) }
        static var description: String { value(.preferencesDescription) }
        static var popupFontSizeLabel: String { value(.preferencesPopupFontSizeLabel) }
        static var popupTooltipDelayLabel: String { value(.preferencesPopupTooltipDelayLabel) }
        static var languageLabel: String { value(.preferencesLanguageLabel) }
        static var targetLanguageLabel: String { value(.preferencesTargetLanguageLabel) }
        static var streamingLabel: String { value(.preferencesStreamingLabel) }
        static var layoutsTitle: String { value(.preferencesLayoutsTitle) }
        static var layoutTitleLabel: String { value(.preferencesLayoutTitleLabel) }
        static var layoutPromptLabel: String { value(.preferencesLayoutPromptLabel) }
        static var addLayout: String { value(.preferencesAddLayout) }
        static var removeLayout: String { value(.preferencesRemoveLayout) }
        static var translationLayoutToggle: String { value(.preferencesTranslationLayoutToggle) }
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
            .layoutEmptyResult: "Result is empty",
            .layoutFailed: "Request failed",
            .layoutLoadingPrefix: "Processing",
            .popupOriginalTitle: "Original",
            .popupTranslationTitle: "Translation",
            .popupCopyTranslation: "Copy Translation",
            .popupCopyAll: "Copy Original + Results",
            .popupOpenPreferences: "Open Preferences",
            .preferencesTitle: "Preferences",
            .preferencesDescription: "Settings are saved automatically.",
            .preferencesPopupFontSizeLabel: "Popup Font Size",
            .preferencesPopupTooltipDelayLabel: "Popup Tooltip Delay (ms)",
            .preferencesLanguageLabel: "Language",
            .preferencesTargetLanguageLabel: "Target Language",
            .preferencesStreamingLabel: "Stream Translation",
            .preferencesLayoutsTitle: "Layouts",
            .preferencesLayoutTitleLabel: "Title",
            .preferencesLayoutPromptLabel: "Prompt",
            .preferencesAddLayout: "Add Layout",
            .preferencesRemoveLayout: "Remove",
            .preferencesTranslationLayoutToggle: "Enable Translation Layout",
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
            .layoutEmptyResult: "结果为空",
            .layoutFailed: "请求失败",
            .layoutLoadingPrefix: "处理中",
            .popupOriginalTitle: "原文",
            .popupTranslationTitle: "译文",
            .popupCopyTranslation: "复制译文",
            .popupCopyAll: "复制原文和结果",
            .popupOpenPreferences: "打开偏好设置",
            .preferencesTitle: "偏好设置",
            .preferencesDescription: "设置会自动保存。",
            .preferencesPopupFontSizeLabel: "弹窗字号",
            .preferencesPopupTooltipDelayLabel: "弹窗提示延迟 (毫秒)",
            .preferencesLanguageLabel: "语言",
            .preferencesTargetLanguageLabel: "目标语言",
            .preferencesStreamingLabel: "流式译文",
            .preferencesLayoutsTitle: "布局",
            .preferencesLayoutTitleLabel: "标题",
            .preferencesLayoutPromptLabel: "提示词",
            .preferencesAddLayout: "添加布局",
            .preferencesRemoveLayout: "移除",
            .preferencesTranslationLayoutToggle: "启用翻译布局",
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
            .layoutEmptyResult: "結果が空です",
            .layoutFailed: "リクエストに失敗しました",
            .layoutLoadingPrefix: "処理中",
            .popupOriginalTitle: "原文",
            .popupTranslationTitle: "翻訳",
            .popupCopyTranslation: "翻訳をコピー",
            .popupCopyAll: "原文と結果をコピー",
            .popupOpenPreferences: "環境設定を開く",
            .preferencesTitle: "環境設定",
            .preferencesDescription: "設定は自動的に保存されます。",
            .preferencesPopupFontSizeLabel: "ポップアップの文字サイズ",
            .preferencesPopupTooltipDelayLabel: "ポップアップのツールチップ遅延 (ミリ秒)",
            .preferencesLanguageLabel: "言語",
            .preferencesTargetLanguageLabel: "翻訳先",
            .preferencesStreamingLabel: "ストリーミング翻訳",
            .preferencesLayoutsTitle: "レイアウト",
            .preferencesLayoutTitleLabel: "タイトル",
            .preferencesLayoutPromptLabel: "プロンプト",
            .preferencesAddLayout: "レイアウトを追加",
            .preferencesRemoveLayout: "削除",
            .preferencesTranslationLayoutToggle: "翻訳レイアウトを有効化",
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
