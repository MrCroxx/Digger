import Carbon
import CoreGraphics
import Foundation

enum AppPreferences {
    static var defaults: UserDefaults {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview") {
            return UserDefaults(suiteName: "com.mrcroxx.digger.preview.preferences")!
        }
        #endif
        return .standard
    }
    static let apiKeyKey = "OpenAIAPIKey"
    static let endpointKey = "OpenAIEndpoint"
    static let modelKey = "OpenAIModel"
    static let thinkEffortKey = "OpenAIThinkEffort"
    static let popupMaxWidthKey = "PopupMaxWidth"
    static let popupMaxHeightKey = "PopupMaxHeight"
    static let popupAutomaticSizeKey = "PopupAutomaticSize"
    static let popupOpacityKey = "PopupOpacity"
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
    static let systemPromptKey = "SystemPrompt"
    static let welcomeCompletedKey = "WelcomeCompleted"
    static let hasLaunchedBeforeKey = "HasLaunchedBefore"
    static let skipWelcomeWhenReadyKey = "SkipWelcomeWhenReady"
    static let startOnLoginKey = "StartOnLogin"

    static let defaultPopupMaxWidth: CGFloat = 640
    static let defaultPopupMaxHeight: CGFloat = 600
    static let defaultPopupOpacity: CGFloat = 100
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
        CustomFunction(id: UUID(uuidString: "70E04CD5-D763-4401-906B-72793E91E101")!, title: "Translation", prompt: PromptTemplates.defaultTranslationPrompt),
        CustomFunction(id: CustomFunction.defaultSummaryID, title: "Summary", prompt: CustomFunction.defaultSummaryPrompt, isEnabled: false)
    ]

    static func apiKey() -> String {
        defaults.string(forKey: apiKeyKey) ?? ""
    }

    static func setApiKey(_ value: String) {
        defaults.set(value, forKey: apiKeyKey)
    }

    static func endpoint() -> String {
        let stored = defaults.string(forKey: endpointKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return stored ?? ""
    }

    static func setEndpoint(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: endpointKey)
        } else {
            defaults.set(trimmed, forKey: endpointKey)
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
        let stored = defaults.string(forKey: modelKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty {
            return stored
        }
        return defaultModel
    }

    static func setModel(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: modelKey)
        } else {
            defaults.set(trimmed, forKey: modelKey)
        }
    }

    static func thinkEffort() -> String {
        defaults.string(forKey: thinkEffortKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func setThinkEffort(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: thinkEffortKey)
        } else {
            defaults.set(trimmed, forKey: thinkEffortKey)
        }
    }

    static func popupMaxWidth() -> CGFloat {
        let stored = defaults.double(forKey: popupMaxWidthKey)
        return stored > 0 ? CGFloat(stored) : defaultPopupMaxWidth
    }

    static func popupAutomaticSize() -> Bool {
        (defaults.object(forKey: popupAutomaticSizeKey) as? Bool) ?? true
    }

    static func setPopupAutomaticSize(_ value: Bool) {
        defaults.set(value, forKey: popupAutomaticSizeKey)
    }

    static func setPopupMaxWidth(_ value: CGFloat) {
        defaults.set(Double(max(value, 360)), forKey: popupMaxWidthKey)
    }

    static func popupMaxHeight() -> CGFloat {
        let stored = defaults.double(forKey: popupMaxHeightKey)
        return stored > 0 ? CGFloat(stored) : defaultPopupMaxHeight
    }

    static func setPopupMaxHeight(_ value: CGFloat) {
        defaults.set(Double(max(value, 160)), forKey: popupMaxHeightKey)
    }

    static func popupOpacity() -> CGFloat {
        if defaults.object(forKey: popupOpacityKey) == nil {
            return defaultPopupOpacity
        }
        let stored = CGFloat(defaults.double(forKey: popupOpacityKey))
        return min(max(stored, 0), 100)
    }

    static func setPopupOpacity(_ value: CGFloat) {
        let clamped = min(max(value, 0), 100)
        defaults.set(Double(clamped), forKey: popupOpacityKey)
    }

    static func popupTooltipDelayMs() -> CGFloat {
        if defaults.object(forKey: popupTooltipDelayMsKey) == nil {
            return defaultPopupTooltipDelayMs
        }
        return CGFloat(defaults.double(forKey: popupTooltipDelayMsKey))
    }

    static func setPopupTooltipDelayMs(_ value: CGFloat) {
        defaults.set(Double(max(value, 0)), forKey: popupTooltipDelayMsKey)
    }

    static func popupOriginalCollapsed() -> Bool {
        (defaults.object(forKey: popupOriginalCollapsedKey) as? Bool) ?? true
    }

    static func setPopupOriginalCollapsed(_ isCollapsed: Bool) {
        defaults.set(isCollapsed, forKey: popupOriginalCollapsedKey)
    }

    static func popupCollapsedFunctionIDs() -> Set<UUID> {
        guard let stored = defaults.array(forKey: popupCollapsedFunctionIDsKey) as? [String] else {
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
        defaults.set(values, forKey: popupCollapsedFunctionIDsKey)
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
        let keyCodeValue = defaults.object(forKey: popupShortcutKeyCodeKey) as? NSNumber
        let modifiersValue = defaults.object(forKey: popupShortcutModifiersKey) as? NSNumber
        let keyCode = keyCodeValue.map { CGKeyCode($0.intValue) } ?? defaultPopupShortcutKeyCode
        let modifiers = modifiersValue.map { CGEventFlags(rawValue: $0.uint64Value) } ?? defaultPopupShortcutModifiers
        return KeyboardShortcut(keyCode: keyCode, modifiers: modifiers)
    }

    static func setPopupShortcut(_ shortcut: KeyboardShortcut) {
        defaults.set(Int(shortcut.keyCode), forKey: popupShortcutKeyCodeKey)
        defaults.set(shortcut.modifiers.rawValue, forKey: popupShortcutModifiersKey)
        NotificationCenter.default.post(name: KeyboardShortcut.didChange, object: nil)
    }

    static func translationStreamingEnabled() -> Bool {
        if defaults.object(forKey: translationStreamingKey) == nil {
            return defaultTranslationStreaming
        }
        return defaults.bool(forKey: translationStreamingKey)
    }

    static func setTranslationStreamingEnabled(_ value: Bool) {
        defaults.set(value, forKey: translationStreamingKey)
    }

    static func translationCacheMaxSizeGiB() -> Double {
        if defaults.object(forKey: translationCacheMaxSizeGiBKey) == nil {
            return defaultTranslationCacheMaxSizeGiB
        }
        let stored = defaults.double(forKey: translationCacheMaxSizeGiBKey)
        return max(stored, 0)
    }

    static func setTranslationCacheMaxSizeGiB(_ value: Double) {
        defaults.set(max(value, 0), forKey: translationCacheMaxSizeGiBKey)
    }

    static func translationCacheMaxBytes() -> Int64 {
        let bytes = translationCacheMaxSizeGiB() * 1_073_741_824
        if bytes >= Double(Int64.max) {
            return Int64.max
        }
        return Int64(bytes.rounded(.down))
    }

    static func translationCacheTTLHours() -> Double {
        if defaults.object(forKey: translationCacheTTLHoursKey) == nil {
            return defaultTranslationCacheTTLHours
        }
        let stored = defaults.double(forKey: translationCacheTTLHoursKey)
        return max(stored, 0)
    }

    static func setTranslationCacheTTLHours(_ value: Double) {
        defaults.set(max(value, 0), forKey: translationCacheTTLHoursKey)
    }

    static func translationCacheTTLSeconds() -> TimeInterval {
        translationCacheTTLHours() * 3600
    }

    static func language() -> AppLanguage {
        let stored = defaults.string(forKey: languageKey)
        return AppLanguage(rawValue: stored ?? "") ?? defaultLanguage
    }

    static func setLanguage(_ language: AppLanguage) {
        defaults.set(language.rawValue, forKey: languageKey)
    }

    static func customFunctions() -> [CustomFunction] {
        guard let data = defaults.data(forKey: customFunctionsKey) else {
            return defaultCustomFunctions
        }
        do {
            return try JSONDecoder().decode([CustomFunction].self, from: data)
        } catch {
            return defaultCustomFunctions
        }
    }

    static func setCustomFunctions(_ functions: [CustomFunction]) {
        do {
            let data = try JSONEncoder().encode(functions)
            defaults.set(data, forKey: customFunctionsKey)
        } catch {
            return
        }
    }

    static func systemPrompt() -> String {
        let stored = defaults.string(forKey: systemPromptKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty {
            return stored
        }
        return defaultSystemPrompt
    }

    static func setSystemPrompt(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: systemPromptKey)
        } else {
            defaults.set(trimmed, forKey: systemPromptKey)
        }
    }

    static func welcomeCompleted() -> Bool {
        defaults.bool(forKey: welcomeCompletedKey)
    }

    static func setWelcomeCompleted(_ value: Bool) {
        defaults.set(value, forKey: welcomeCompletedKey)
    }

    static func hasLaunchedBefore() -> Bool {
        defaults.bool(forKey: hasLaunchedBeforeKey)
    }

    static func setHasLaunchedBefore(_ value: Bool) {
        defaults.set(value, forKey: hasLaunchedBeforeKey)
    }

    static func skipWelcomeWhenReady() -> Bool {
        defaults.bool(forKey: skipWelcomeWhenReadyKey)
    }

    static func setSkipWelcomeWhenReady(_ value: Bool) {
        defaults.set(value, forKey: skipWelcomeWhenReadyKey)
    }

    static func startOnLoginEnabled() -> Bool {
        defaults.bool(forKey: startOnLoginKey)
    }

    static func setStartOnLoginEnabled(_ value: Bool) {
        defaults.set(value, forKey: startOnLoginKey)
    }

    static func clearCustomFunctions() {
        defaults.removeObject(forKey: customFunctionsKey)
    }

}
