import CoreGraphics
import Foundation

enum AppPreferences {
    static let apiKeyKey = "OpenAIAPIKey"
    static let endpointKey = "OpenAIEndpoint"
    static let pressureThresholdKey = "ForceClickPressureThreshold"
    static let pressureDeltaKey = "ForceClickPressureDelta"
    static let baselineWindowKey = "ForceClickBaselineWindowMs"
    static let popupMaxWidthKey = "PopupMaxWidth"
    static let popupMaxHeightKey = "PopupMaxHeight"
    static let languageKey = "AppLanguage"
    static let translationTargetLanguageKey = "TranslationTargetLanguage"

    static let defaultThreshold: CGFloat = 3.0
    static let defaultDelta: CGFloat = 2.0
    static let defaultBaselineWindowMs: CGFloat = 120
    static let defaultPopupMaxWidth: CGFloat = 520
    static let defaultPopupMaxHeight: CGFloat = 360
    static let defaultLanguage: AppLanguage = .english
    static let defaultTranslationTargetLanguage: TranslationTargetLanguage = .chineseSimplified

    static func apiKey() -> String {
        UserDefaults.standard.string(forKey: apiKeyKey) ?? ""
    }

    static func setApiKey(_ value: String) {
        UserDefaults.standard.set(value, forKey: apiKeyKey)
    }

    static func endpoint() -> String {
        UserDefaults.standard.string(forKey: endpointKey) ?? ""
    }

    static func setEndpoint(_ value: String) {
        UserDefaults.standard.set(value, forKey: endpointKey)
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

    static func language() -> AppLanguage {
        let stored = UserDefaults.standard.string(forKey: languageKey)
        return AppLanguage(rawValue: stored ?? "") ?? defaultLanguage
    }

    static func setLanguage(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: languageKey)
    }

    static func translationTargetLanguage() -> TranslationTargetLanguage {
        let stored = UserDefaults.standard.string(forKey: translationTargetLanguageKey)
        return TranslationTargetLanguage(rawValue: stored ?? "") ?? defaultTranslationTargetLanguage
    }

    static func setTranslationTargetLanguage(_ language: TranslationTargetLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: translationTargetLanguageKey)
    }
}
