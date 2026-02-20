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
        case popupRetry
        case popupCopyTranslationSuccess
        case popupCopyResultSuccess
        case popupCopyAllSuccess
        case popupCopyAllWithoutOriginalSuccess
        case popupCopyAllWithOriginalSuccess
        case popupProcessingPrefix
        case popupEmptyResult
        case popupEmptyPrompt
        case popupUntitledFunction
        case popupCollapseResult
        case popupExpandResult
        case popupCacheHit
        case preferencesTitle
        case preferencesDescription
        case preferencesTabGeneral
        case preferencesTabPopup
        case preferencesTabFunctions
        case preferencesTabAdvanced
        case preferencesTabAPI
        case preferencesTabCache
        case preferencesPopupFontSizeLabel
        case preferencesPopupOpacityLabel
        case preferencesPopupTooltipDelayLabel
        case preferencesPopupShortcutLabel
        case preferencesPopupShortcutPlaceholder
        case preferencesLanguageLabel
        case preferencesStreamingLabel
        case preferencesStartOnLoginLabel
        case preferencesCustomFunctionsTitle
        case preferencesCustomFunctionsDescription
        case preferencesSystemPromptTitle
        case preferencesSystemPromptDescription
        case preferencesSystemPromptPlaceholder
        case preferencesFunctionTitleLabel
        case preferencesFunctionPromptLabel
        case preferencesAddFunction
        case preferencesRemoveFunction
        case preferencesFunctionTitlePlaceholder
        case preferencesFunctionPromptPlaceholder
        case preferencesFunctionDefaultTitle
        case preferencesRestorePromptsLabel
        case preferencesApiTestLabel
        case preferencesApiTestButton
        case preferencesApiTestInProgress
        case preferencesApiTestSuccess
        case preferencesApiTestFailedPrefix
        case preferencesApiTestMissingKey
        case preferencesApiTestMissingModel
        case preferencesCacheMaxSizeLabel
        case preferencesCacheTTLHoursLabel
        case preferencesOpenCacheDirectoryButton
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
        case menuWindow
        case menuClose
        case welcomeTitle
        case welcomeSubtitle
        case welcomeAccessibilityTitle
        case welcomeAccessibilityDescription
        case welcomeOpenAccessibilityButton
        case welcomeLookupDataDetectorsTitle
        case welcomeLookupDataDetectorsDescription
        case welcomeOpenTrackpadButton
        case welcomeSkipNextTimeLabel
        case welcomeStartButton
        case welcomeStatusReady
        case welcomeStatusMissing
        case menuOpenWelcome
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
        static var retry: String { value(.popupRetry) }
        static var copyTranslationSuccess: String { value(.popupCopyTranslationSuccess) }
        static var copyResultSuccess: String { value(.popupCopyResultSuccess) }
        static var copyAllSuccess: String { value(.popupCopyAllSuccess) }
        static var copyAllWithoutOriginalSuccess: String { value(.popupCopyAllWithoutOriginalSuccess) }
        static var copyAllWithOriginalSuccess: String { value(.popupCopyAllWithOriginalSuccess) }
        static var processingPrefix: String { value(.popupProcessingPrefix) }
        static var emptyResult: String { value(.popupEmptyResult) }
        static var emptyPrompt: String { value(.popupEmptyPrompt) }
        static var untitledFunction: String { value(.popupUntitledFunction) }
        static var collapseResult: String { value(.popupCollapseResult) }
        static var expandResult: String { value(.popupExpandResult) }
        static var cacheHit: String { value(.popupCacheHit) }
    }

    enum Preferences {
        static var title: String { value(.preferencesTitle) }
        static var description: String { value(.preferencesDescription) }
        static var tabGeneral: String { value(.preferencesTabGeneral) }
        static var tabPopup: String { value(.preferencesTabPopup) }
        static var tabFunctions: String { value(.preferencesTabFunctions) }
        static var tabAdvanced: String { value(.preferencesTabAdvanced) }
        static var tabAPI: String { value(.preferencesTabAPI) }
        static var tabCache: String { value(.preferencesTabCache) }
        static var popupFontSizeLabel: String { value(.preferencesPopupFontSizeLabel) }
        static var popupOpacityLabel: String { value(.preferencesPopupOpacityLabel) }
        static var popupTooltipDelayLabel: String { value(.preferencesPopupTooltipDelayLabel) }
        static var popupShortcutLabel: String { value(.preferencesPopupShortcutLabel) }
        static var popupShortcutPlaceholder: String { value(.preferencesPopupShortcutPlaceholder) }
        static var languageLabel: String { value(.preferencesLanguageLabel) }
        static var streamingLabel: String { value(.preferencesStreamingLabel) }
        static var startOnLoginLabel: String { value(.preferencesStartOnLoginLabel) }
        static var customFunctionsTitle: String { value(.preferencesCustomFunctionsTitle) }
        static var customFunctionsDescription: String { value(.preferencesCustomFunctionsDescription) }
        static var systemPromptTitle: String { value(.preferencesSystemPromptTitle) }
        static var systemPromptDescription: String { value(.preferencesSystemPromptDescription) }
        static var systemPromptPlaceholder: String { value(.preferencesSystemPromptPlaceholder) }
        static var functionTitleLabel: String { value(.preferencesFunctionTitleLabel) }
        static var functionPromptLabel: String { value(.preferencesFunctionPromptLabel) }
        static var addFunction: String { value(.preferencesAddFunction) }
        static var removeFunction: String { value(.preferencesRemoveFunction) }
        static var functionTitlePlaceholder: String { value(.preferencesFunctionTitlePlaceholder) }
        static var functionPromptPlaceholder: String { value(.preferencesFunctionPromptPlaceholder) }
        static var functionDefaultTitle: String { value(.preferencesFunctionDefaultTitle) }
        static var restorePromptsLabel: String { value(.preferencesRestorePromptsLabel) }
        static var apiTestLabel: String { value(.preferencesApiTestLabel) }
        static var apiTestButton: String { value(.preferencesApiTestButton) }
        static var apiTestInProgress: String { value(.preferencesApiTestInProgress) }
        static var apiTestSuccess: String { value(.preferencesApiTestSuccess) }
        static var apiTestFailedPrefix: String { value(.preferencesApiTestFailedPrefix) }
        static var apiTestMissingKey: String { value(.preferencesApiTestMissingKey) }
        static var apiTestMissingModel: String { value(.preferencesApiTestMissingModel) }
        static var cacheMaxSizeLabel: String { value(.preferencesCacheMaxSizeLabel) }
        static var cacheTTLHoursLabel: String { value(.preferencesCacheTTLHoursLabel) }
        static var openCacheDirectoryButton: String { value(.preferencesOpenCacheDirectoryButton) }
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
        static var window: String { value(.menuWindow) }
        static var close: String { value(.menuClose) }
        static var openWelcome: String { value(.menuOpenWelcome) }
    }

    enum Welcome {
        static var title: String { value(.welcomeTitle) }
        static var subtitle: String { value(.welcomeSubtitle) }
        static var accessibilityTitle: String { value(.welcomeAccessibilityTitle) }
        static var accessibilityDescription: String { value(.welcomeAccessibilityDescription) }
        static var openAccessibilityButton: String { value(.welcomeOpenAccessibilityButton) }
        static var lookupDataDetectorsTitle: String { value(.welcomeLookupDataDetectorsTitle) }
        static var lookupDataDetectorsDescription: String { value(.welcomeLookupDataDetectorsDescription) }
        static var openTrackpadButton: String { value(.welcomeOpenTrackpadButton) }
        static var skipNextTimeLabel: String { value(.welcomeSkipNextTimeLabel) }
        static var startButton: String { value(.welcomeStartButton) }
        static var statusReady: String { value(.welcomeStatusReady) }
        static var statusMissing: String { value(.welcomeStatusMissing) }
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
            .popupRetry: "Retry Query",
            .popupCopyTranslationSuccess: "Translation copied",
            .popupCopyResultSuccess: "Result copied",
            .popupCopyAllSuccess: "All results copied",
            .popupCopyAllWithoutOriginalSuccess: "Results copied (without original)",
            .popupCopyAllWithOriginalSuccess: "Results copied (with original)",
            .popupProcessingPrefix: "Processing",
            .popupEmptyResult: "Result is empty",
            .popupEmptyPrompt: "Prompt is empty",
            .popupUntitledFunction: "Untitled Prompt",
            .popupCollapseResult: "Collapse Result",
            .popupExpandResult: "Expand Result",
            .popupCacheHit: "Cache hit",
            .preferencesTitle: "Preferences",
            .preferencesDescription: "Settings are saved automatically.",
            .preferencesTabGeneral: "General",
            .preferencesTabPopup: "Popup",
            .preferencesTabFunctions: "Prompts",
            .preferencesTabAdvanced: "Advanced",
            .preferencesTabAPI: "API",
            .preferencesTabCache: "Cache",
            .preferencesPopupFontSizeLabel: "Popup Font Size",
            .preferencesPopupOpacityLabel: "Popup Opacity",
            .preferencesPopupTooltipDelayLabel: "Popup Tooltip Delay (ms)",
            .preferencesPopupShortcutLabel: "Trigger Shortcut",
            .preferencesPopupShortcutPlaceholder: "Press shortcut",
            .preferencesLanguageLabel: "Language",
            .preferencesStreamingLabel: "Stream Output",
            .preferencesStartOnLoginLabel: "Start on Login",
            .preferencesCustomFunctionsTitle: "Custom Prompts",
            .preferencesCustomFunctionsDescription: "Add prompts that apply to selected text.",
            .preferencesSystemPromptTitle: "System Prompt",
            .preferencesSystemPromptDescription: "Applied to all prompts, including translation.",
            .preferencesSystemPromptPlaceholder: "Enter system prompt",
            .preferencesFunctionTitleLabel: "Title",
            .preferencesFunctionPromptLabel: "Prompt",
            .preferencesAddFunction: "Add Prompt",
            .preferencesRemoveFunction: "Remove",
            .preferencesFunctionTitlePlaceholder: "Prompt title",
            .preferencesFunctionPromptPlaceholder: "Enter prompt",
            .preferencesFunctionDefaultTitle: "New Prompt",
            .preferencesRestorePromptsLabel: "Restore Prompts",
            .preferencesApiTestLabel: "Test API",
            .preferencesApiTestButton: "Test",
            .preferencesApiTestInProgress: "Testing…",
            .preferencesApiTestSuccess: "API configuration looks good",
            .preferencesApiTestFailedPrefix: "Test failed:",
            .preferencesApiTestMissingKey: "Please enter an API key first",
            .preferencesApiTestMissingModel: "Please enter a model first",
            .preferencesCacheMaxSizeLabel: "Cache Max Size (GiB)",
            .preferencesCacheTTLHoursLabel: "Cache TTL (Hours)",
            .preferencesOpenCacheDirectoryButton: "Open Cache Directory",
            .menuPreferences: "Preferences",
            .menuQuit: "Quit Digger",
            .menuEdit: "Edit",
            .menuUndo: "Undo",
            .menuRedo: "Redo",
            .menuCut: "Cut",
            .menuCopy: "Copy",
            .menuPaste: "Paste",
            .menuSelectAll: "Select All",
            .menuAppTitle: "Digger",
            .menuWindow: "Window",
            .menuClose: "Close",
            .menuOpenWelcome: "Open Welcome",
            .welcomeTitle: "Welcome to Digger",
            .welcomeSubtitle: "To get started, enable the permissions below in System Settings.",
            .welcomeAccessibilityTitle: "Accessibility",
            .welcomeAccessibilityDescription: "Allows Digger to read selected text and listen for shortcuts.",
            .welcomeOpenAccessibilityButton: "Open Accessibility Settings",
            .welcomeLookupDataDetectorsTitle: "Turn Off Look Up & Data Detectors",
            .welcomeLookupDataDetectorsDescription: "Turn off Look Up & Data Detectors in Trackpad settings.\nIt helps avoid conflicts with Digger.",
            .welcomeOpenTrackpadButton: "Open Trackpad Settings",
            .welcomeSkipNextTimeLabel: "Skip welcome next time when permissions are ready",
            .welcomeStartButton: "Get Started",
            .welcomeStatusReady: "All permissions are ready",
            .welcomeStatusMissing: "Permissions required"
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
            .popupRetry: "重试查询",
            .popupCopyTranslationSuccess: "译文已复制",
            .popupCopyResultSuccess: "结果已复制",
            .popupCopyAllSuccess: "结果已复制",
            .popupCopyAllWithoutOriginalSuccess: "已复制结果（不含原文）",
            .popupCopyAllWithOriginalSuccess: "已复制结果（含原文）",
            .popupProcessingPrefix: "处理中",
            .popupEmptyResult: "结果为空",
            .popupEmptyPrompt: "提示语为空",
            .popupUntitledFunction: "未命名提示语",
            .popupCollapseResult: "收起结果",
            .popupExpandResult: "展开结果",
            .popupCacheHit: "缓存命中",
            .preferencesTitle: "偏好设置",
            .preferencesDescription: "设置会自动保存。",
            .preferencesTabGeneral: "通用",
            .preferencesTabPopup: "弹窗",
            .preferencesTabFunctions: "提示语",
            .preferencesTabAdvanced: "高级",
            .preferencesTabAPI: "API",
            .preferencesTabCache: "缓存",
            .preferencesPopupFontSizeLabel: "弹窗字号",
            .preferencesPopupOpacityLabel: "弹窗透明度",
            .preferencesPopupTooltipDelayLabel: "弹窗提示延迟 (毫秒)",
            .preferencesPopupShortcutLabel: "触发快捷键",
            .preferencesPopupShortcutPlaceholder: "按下快捷键",
            .preferencesLanguageLabel: "语言",
            .preferencesStreamingLabel: "流式输出",
            .preferencesStartOnLoginLabel: "登录时启动",
            .preferencesCustomFunctionsTitle: "自定义提示语",
            .preferencesCustomFunctionsDescription: "添加应用于选中文本的提示语。",
            .preferencesSystemPromptTitle: "系统提示语",
            .preferencesSystemPromptDescription: "应用于所有提示语，包括翻译。",
            .preferencesSystemPromptPlaceholder: "输入系统提示语",
            .preferencesFunctionTitleLabel: "标题",
            .preferencesFunctionPromptLabel: "提示语",
            .preferencesAddFunction: "添加提示语",
            .preferencesRemoveFunction: "删除",
            .preferencesFunctionTitlePlaceholder: "提示语标题",
            .preferencesFunctionPromptPlaceholder: "输入提示语",
            .preferencesFunctionDefaultTitle: "新提示语",
            .preferencesRestorePromptsLabel: "还原提示语",
            .preferencesApiTestLabel: "测试 API",
            .preferencesApiTestButton: "测试",
            .preferencesApiTestInProgress: "测试中…",
            .preferencesApiTestSuccess: "API 配置正常",
            .preferencesApiTestFailedPrefix: "测试失败:",
            .preferencesApiTestMissingKey: "请先输入 API Key",
            .preferencesApiTestMissingModel: "请先输入模型",
            .preferencesCacheMaxSizeLabel: "缓存上限 (GiB)",
            .preferencesCacheTTLHoursLabel: "缓存过期时间 (小时)",
            .preferencesOpenCacheDirectoryButton: "打开缓存目录",
            .menuPreferences: "偏好设置",
            .menuQuit: "退出 Digger",
            .menuEdit: "编辑",
            .menuUndo: "撤销",
            .menuRedo: "重做",
            .menuCut: "剪切",
            .menuCopy: "复制",
            .menuPaste: "粘贴",
            .menuSelectAll: "全选",
            .menuAppTitle: "Digger",
            .menuWindow: "窗口",
            .menuClose: "关闭",
            .menuOpenWelcome: "打开欢迎页",
            .welcomeTitle: "欢迎使用 Digger",
            .welcomeSubtitle: "开始使用前，请在系统设置中开启以下权限。",
            .welcomeAccessibilityTitle: "辅助功能",
            .welcomeAccessibilityDescription: "用于读取选中文本并监听快捷键。",
            .welcomeOpenAccessibilityButton: "打开辅助功能设置",
            .welcomeLookupDataDetectorsTitle: "关闭“查询与数据检测器”",
            .welcomeLookupDataDetectorsDescription: "请在触控板设置中关闭“查询与数据检测器”。\n这样可以避免与 Digger 冲突。",
            .welcomeOpenTrackpadButton: "打开触控板设置",
            .welcomeSkipNextTimeLabel: "下次权限已就绪时跳过欢迎页",
            .welcomeStartButton: "开始使用",
            .welcomeStatusReady: "权限已就绪",
            .welcomeStatusMissing: "需要授权"
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
            .popupRetry: "再試行",
            .popupCopyTranslationSuccess: "翻訳をコピーしました",
            .popupCopyResultSuccess: "結果をコピーしました",
            .popupCopyAllSuccess: "結果をコピーしました",
            .popupCopyAllWithoutOriginalSuccess: "結果をコピーしました（原文なし）",
            .popupCopyAllWithOriginalSuccess: "結果をコピーしました（原文あり）",
            .popupProcessingPrefix: "処理中",
            .popupEmptyResult: "結果が空です",
            .popupEmptyPrompt: "プロンプトが空です",
            .popupUntitledFunction: "無題のプロンプト",
            .popupCollapseResult: "結果を折りたたむ",
            .popupExpandResult: "結果を展開",
            .popupCacheHit: "キャッシュヒット",
            .preferencesTitle: "環境設定",
            .preferencesDescription: "設定は自動的に保存されます。",
            .preferencesTabGeneral: "一般",
            .preferencesTabPopup: "ポップアップ",
            .preferencesTabFunctions: "プロンプト",
            .preferencesTabAdvanced: "詳細",
            .preferencesTabAPI: "API",
            .preferencesTabCache: "キャッシュ",
            .preferencesPopupFontSizeLabel: "ポップアップの文字サイズ",
            .preferencesPopupOpacityLabel: "ポップアップの透明度",
            .preferencesPopupTooltipDelayLabel: "ポップアップのツールチップ遅延 (ミリ秒)",
            .preferencesPopupShortcutLabel: "トリガーショートカット",
            .preferencesPopupShortcutPlaceholder: "ショートカットを入力",
            .preferencesLanguageLabel: "言語",
            .preferencesStreamingLabel: "ストリーミング出力",
            .preferencesStartOnLoginLabel: "ログイン時に起動",
            .preferencesCustomFunctionsTitle: "カスタムプロンプト",
            .preferencesCustomFunctionsDescription: "選択したテキストに適用するプロンプトを追加します。",
            .preferencesSystemPromptTitle: "システムプロンプト",
            .preferencesSystemPromptDescription: "翻訳を含むすべてのプロンプトに適用されます。",
            .preferencesSystemPromptPlaceholder: "システムプロンプトを入力",
            .preferencesFunctionTitleLabel: "タイトル",
            .preferencesFunctionPromptLabel: "プロンプト",
            .preferencesAddFunction: "プロンプトを追加",
            .preferencesRemoveFunction: "削除",
            .preferencesFunctionTitlePlaceholder: "プロンプトタイトル",
            .preferencesFunctionPromptPlaceholder: "プロンプトを入力",
            .preferencesFunctionDefaultTitle: "新規プロンプト",
            .preferencesRestorePromptsLabel: "プロンプトを復元",
            .preferencesApiTestLabel: "API テスト",
            .preferencesApiTestButton: "テスト",
            .preferencesApiTestInProgress: "テスト中…",
            .preferencesApiTestSuccess: "API 設定は正常です",
            .preferencesApiTestFailedPrefix: "テストに失敗しました:",
            .preferencesApiTestMissingKey: "API Key を入力してください",
            .preferencesApiTestMissingModel: "モデルを入力してください",
            .preferencesCacheMaxSizeLabel: "キャッシュ上限 (GiB)",
            .preferencesCacheTTLHoursLabel: "キャッシュ有効期限 (時間)",
            .preferencesOpenCacheDirectoryButton: "キャッシュフォルダを開く",
            .menuPreferences: "環境設定",
            .menuQuit: "Digger を終了",
            .menuEdit: "編集",
            .menuUndo: "取り消す",
            .menuRedo: "やり直す",
            .menuCut: "切り取り",
            .menuCopy: "コピー",
            .menuPaste: "貼り付け",
            .menuSelectAll: "すべて選択",
            .menuAppTitle: "Digger",
            .menuWindow: "ウインドウ",
            .menuClose: "閉じる",
            .menuOpenWelcome: "ウェルカム画面を開く",
            .welcomeTitle: "Digger へようこそ",
            .welcomeSubtitle: "使用を開始するには、システム設定で以下の権限を有効にしてください。",
            .welcomeAccessibilityTitle: "アクセシビリティ",
            .welcomeAccessibilityDescription: "選択したテキストの取得とショートカットの検知に必要です。",
            .welcomeOpenAccessibilityButton: "アクセシビリティ設定を開く",
            .welcomeLookupDataDetectorsTitle: "調べる & データ検出をオフにする",
            .welcomeLookupDataDetectorsDescription: "トラックパッド設定で「調べる & データ検出」をオフにしてください。\nDigger との競合を避けるためです。",
            .welcomeOpenTrackpadButton: "トラックパッド設定を開く",
            .welcomeSkipNextTimeLabel: "次回、権限が揃っている場合はウェルカム画面をスキップ",
            .welcomeStartButton: "開始する",
            .welcomeStatusReady: "権限は準備完了です",
            .welcomeStatusMissing: "権限が必要です"
        ]
    ]
}
