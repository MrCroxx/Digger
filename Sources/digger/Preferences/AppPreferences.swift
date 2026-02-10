import Carbon
import CoreGraphics
import Foundation

enum AppPreferences {
    static let apiKeyKey = "OpenAIAPIKey"
    static let endpointKey = "OpenAIEndpoint"
    static let modelKey = "OpenAIModel"
    static let pressureThresholdKey = "ForceClickPressureThreshold"
    static let pressureDeltaKey = "ForceClickPressureDelta"
    static let baselineWindowKey = "ForceClickBaselineWindowMs"
    static let popupMaxWidthKey = "PopupMaxWidth"
    static let popupMaxHeightKey = "PopupMaxHeight"
    static let popupTooltipDelayMsKey = "PopupTooltipDelayMs"
    static let popupCollapsedFunctionIDsKey = "PopupCollapsedFunctionIDs"
    static let popupOriginalCollapsedKey = "PopupOriginalCollapsed"
    static let popupShortcutKeyCodeKey = "PopupShortcutKeyCode"
    static let popupShortcutModifiersKey = "PopupShortcutModifiers"
    static let translationStreamingKey = "TranslationStreaming"
    static let translationCacheMaxSizeGiBKey = "TranslationCacheMaxSizeGiB"
    static let translationCacheTTLHoursKey = "TranslationCacheTTLHours"
    static let languageKey = "AppLanguage"
    static let customFunctionsKey = "CustomFunctions"
    static let customFunctionsClearedKey = "CustomFunctionsClearedOnceV2"
    static let systemPromptKey = "SystemPrompt"
    static let welcomeCompletedKey = "WelcomeCompleted"
    static let hasLaunchedBeforeKey = "HasLaunchedBefore"
    static let skipWelcomeWhenReadyKey = "SkipWelcomeWhenReady"
    static let startOnLoginKey = "StartOnLogin"

    static let defaultThreshold: CGFloat = 3.0
    static let defaultDelta: CGFloat = 55.0
    static let defaultBaselineWindowMs: CGFloat = 120
    static let defaultPopupMaxWidth: CGFloat = 640
    static let defaultPopupMaxHeight: CGFloat = 480
    static let defaultPopupTooltipDelayMs: CGFloat = 300
    static let defaultPopupShortcutKeyCode: CGKeyCode = CGKeyCode(kVK_ANSI_E)
    static let defaultPopupShortcutModifiers: CGEventFlags = [.maskCommand]
    static let defaultTranslationStreaming = true
    static let defaultTranslationCacheMaxSizeGiB = 1.0
    static let defaultTranslationCacheTTLHours = 168.0
    static let defaultLanguage: AppLanguage = .english
    static let defaultModel = "gpt-4.1-mini"
    static let defaultEndpoint = "https://api.openai.com/v1"
    static let defaultSystemPrompt = "Only return the result, without extra output."
    static let defaultCustomFunctions: [CustomFunction] = [
        CustomFunction(title: "Translation", prompt: PromptTemplates.defaultTranslationPrompt),
        CustomFunction(title: "Summary", prompt: "Summarize it in one sentence.")
    ]

    static func apiKey() -> String {
        UserDefaults.standard.string(forKey: apiKeyKey) ?? ""
    }

    static func setApiKey(_ value: String) {
        UserDefaults.standard.set(value, forKey: apiKeyKey)
    }

    static func endpoint() -> String {
        let stored = UserDefaults.standard.string(forKey: endpointKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return stored ?? ""
    }

    static func setEndpoint(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: endpointKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: endpointKey)
        }
    }

    static func endpointOrDefault() -> String {
        resolvedEndpoint(endpoint())
    }

    static func resolvedEndpoint(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return defaultEndpoint
        }
        return trimmed
    }

    static func model() -> String {
        let stored = UserDefaults.standard.string(forKey: modelKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty {
            return stored
        }
        return defaultModel
    }

    static func setModel(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: modelKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: modelKey)
        }
    }

    static func pressureThreshold() -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: pressureThresholdKey)
        return stored > 0 ? CGFloat(stored) : defaultThreshold
    }

    static func setPressureThreshold(_ value: CGFloat) {
        UserDefaults.standard.set(Double(max(value, 0.1)), forKey: pressureThresholdKey)
    }

    static func pressureDelta() -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: pressureDeltaKey)
        return stored > 0 ? CGFloat(stored) : defaultDelta
    }

    static func setPressureDelta(_ value: CGFloat) {
        UserDefaults.standard.set(Double(max(value, 0.1)), forKey: pressureDeltaKey)
    }

    static func baselineWindowMs() -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: baselineWindowKey)
        return stored > 0 ? CGFloat(stored) : defaultBaselineWindowMs
    }

    static func setBaselineWindowMs(_ value: CGFloat) {
        UserDefaults.standard.set(Double(max(value, 10)), forKey: baselineWindowKey)
    }

    static func popupMaxWidth() -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: popupMaxWidthKey)
        return stored > 0 ? CGFloat(stored) : defaultPopupMaxWidth
    }

    static func setPopupMaxWidth(_ value: CGFloat) {
        UserDefaults.standard.set(Double(max(value, 200)), forKey: popupMaxWidthKey)
    }

    static func popupMaxHeight() -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: popupMaxHeightKey)
        return stored > 0 ? CGFloat(stored) : defaultPopupMaxHeight
    }

    static func setPopupMaxHeight(_ value: CGFloat) {
        UserDefaults.standard.set(Double(max(value, 120)), forKey: popupMaxHeightKey)
    }

    static func popupTooltipDelayMs() -> CGFloat {
        if UserDefaults.standard.object(forKey: popupTooltipDelayMsKey) == nil {
            return defaultPopupTooltipDelayMs
        }
        return CGFloat(UserDefaults.standard.double(forKey: popupTooltipDelayMsKey))
    }

    static func setPopupTooltipDelayMs(_ value: CGFloat) {
        UserDefaults.standard.set(Double(max(value, 0)), forKey: popupTooltipDelayMsKey)
    }

    static func popupOriginalCollapsed() -> Bool {
        UserDefaults.standard.bool(forKey: popupOriginalCollapsedKey)
    }

    static func setPopupOriginalCollapsed(_ isCollapsed: Bool) {
        UserDefaults.standard.set(isCollapsed, forKey: popupOriginalCollapsedKey)
    }

    static func popupCollapsedFunctionIDs() -> Set<UUID> {
        guard let stored = UserDefaults.standard.array(forKey: popupCollapsedFunctionIDsKey) as? [String] else {
            return []
        }
        var ids = Set<UUID>()
        var hadInvalid = false
        for value in stored {
            if let id = UUID(uuidString: value) {
                ids.insert(id)
            } else {
                hadInvalid = true
            }
        }
        if hadInvalid {
            setPopupCollapsedFunctionIDs(ids)
        }
        return ids
    }

    static func setPopupCollapsedFunctionIDs(_ ids: Set<UUID>) {
        let values = ids.map { $0.uuidString }.sorted()
        UserDefaults.standard.set(values, forKey: popupCollapsedFunctionIDsKey)
    }

    static func setPopupFunctionCollapsed(_ id: UUID, isCollapsed: Bool) {
        var ids = popupCollapsedFunctionIDs()
        if isCollapsed {
            ids.insert(id)
        } else {
            ids.remove(id)
        }
        setPopupCollapsedFunctionIDs(ids)
    }

    static func popupShortcut() -> KeyboardShortcut {
        let keyCodeValue = UserDefaults.standard.object(forKey: popupShortcutKeyCodeKey) as? NSNumber
        let modifiersValue = UserDefaults.standard.object(forKey: popupShortcutModifiersKey) as? NSNumber
        let keyCode = keyCodeValue.map { CGKeyCode($0.intValue) } ?? defaultPopupShortcutKeyCode
        let modifiers = modifiersValue.map { CGEventFlags(rawValue: $0.uint64Value) } ?? defaultPopupShortcutModifiers
        return KeyboardShortcut(keyCode: keyCode, modifiers: modifiers)
    }

    static func setPopupShortcut(_ shortcut: KeyboardShortcut) {
        UserDefaults.standard.set(Int(shortcut.keyCode), forKey: popupShortcutKeyCodeKey)
        UserDefaults.standard.set(shortcut.modifiers.rawValue, forKey: popupShortcutModifiersKey)
    }

    static func translationStreamingEnabled() -> Bool {
        if UserDefaults.standard.object(forKey: translationStreamingKey) == nil {
            return defaultTranslationStreaming
        }
        return UserDefaults.standard.bool(forKey: translationStreamingKey)
    }

    static func setTranslationStreamingEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: translationStreamingKey)
    }

    static func translationCacheMaxSizeGiB() -> Double {
        if UserDefaults.standard.object(forKey: translationCacheMaxSizeGiBKey) == nil {
            return defaultTranslationCacheMaxSizeGiB
        }
        let stored = UserDefaults.standard.double(forKey: translationCacheMaxSizeGiBKey)
        return max(stored, 0)
    }

    static func setTranslationCacheMaxSizeGiB(_ value: Double) {
        UserDefaults.standard.set(max(value, 0), forKey: translationCacheMaxSizeGiBKey)
    }

    static func translationCacheMaxBytes() -> Int64 {
        let bytes = translationCacheMaxSizeGiB() * 1_073_741_824
        if bytes >= Double(Int64.max) {
            return Int64.max
        }
        return Int64(bytes.rounded(.down))
    }

    static func translationCacheTTLHours() -> Double {
        if UserDefaults.standard.object(forKey: translationCacheTTLHoursKey) == nil {
            return defaultTranslationCacheTTLHours
        }
        let stored = UserDefaults.standard.double(forKey: translationCacheTTLHoursKey)
        return max(stored, 0)
    }

    static func setTranslationCacheTTLHours(_ value: Double) {
        UserDefaults.standard.set(max(value, 0), forKey: translationCacheTTLHoursKey)
    }

    static func translationCacheTTLSeconds() -> TimeInterval {
        translationCacheTTLHours() * 3600
    }

    static func language() -> AppLanguage {
        let stored = UserDefaults.standard.string(forKey: languageKey)
        return AppLanguage(rawValue: stored ?? "") ?? defaultLanguage
    }

    static func setLanguage(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: languageKey)
    }

    static func customFunctions() -> [CustomFunction] {
        guard let data = UserDefaults.standard.data(forKey: customFunctionsKey) else {
            return defaultCustomFunctions
        }
        do {
            return try JSONDecoder().decode([CustomFunction].self, from: data)
        } catch {
            UserDefaults.standard.removeObject(forKey: customFunctionsKey)
            return defaultCustomFunctions
        }
    }

    static func setCustomFunctions(_ functions: [CustomFunction]) {
        do {
            let data = try JSONEncoder().encode(functions)
            UserDefaults.standard.set(data, forKey: customFunctionsKey)
        } catch {
            return
        }
    }

    static func systemPrompt() -> String {
        let stored = UserDefaults.standard.string(forKey: systemPromptKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty {
            return stored
        }
        return defaultSystemPrompt
    }

    static func setSystemPrompt(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: systemPromptKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: systemPromptKey)
        }
    }

    static func welcomeCompleted() -> Bool {
        UserDefaults.standard.bool(forKey: welcomeCompletedKey)
    }

    static func setWelcomeCompleted(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: welcomeCompletedKey)
    }

    static func hasLaunchedBefore() -> Bool {
        UserDefaults.standard.bool(forKey: hasLaunchedBeforeKey)
    }

    static func setHasLaunchedBefore(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: hasLaunchedBeforeKey)
    }

    static func skipWelcomeWhenReady() -> Bool {
        UserDefaults.standard.bool(forKey: skipWelcomeWhenReadyKey)
    }

    static func setSkipWelcomeWhenReady(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: skipWelcomeWhenReadyKey)
    }

    static func startOnLoginEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: startOnLoginKey)
    }

    static func setStartOnLoginEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: startOnLoginKey)
    }

    static func clearCustomFunctions() {
        UserDefaults.standard.removeObject(forKey: customFunctionsKey)
    }

    static func clearCustomFunctionsOnceIfNeeded() {
        if UserDefaults.standard.bool(forKey: customFunctionsClearedKey) {
            return
        }
        clearCustomFunctions()
        UserDefaults.standard.set(true, forKey: customFunctionsClearedKey)
    }

}
