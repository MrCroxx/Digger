import Foundation

@MainActor
final class PreferencesViewModel: ObservableObject {
    @Published var language: AppLanguage = AppPreferences.language()
    @Published var targetLanguage: TranslationTargetLanguage = AppPreferences.translationTargetLanguage()
    @Published var streamingEnabled: Bool = AppPreferences.translationStreamingEnabled()
    @Published var popupFontSize: Double = Double(PopupFontPreferences.load())
    @Published var popupTooltipDelayText: String = String(format: "%.0f", AppPreferences.popupTooltipDelayMs())
    @Published var popupMaxWidthText: String = String(format: "%.0f", AppPreferences.popupMaxWidth())
    @Published var popupMaxHeightText: String = String(format: "%.0f", AppPreferences.popupMaxHeight())
    @Published var popupShortcut: KeyboardShortcut = AppPreferences.popupShortcut()
    @Published var apiKey: String = AppPreferences.apiKey()
    @Published var endpoint: String = AppPreferences.endpoint()
    @Published var pressureThresholdText: String = String(format: "%.2f", AppPreferences.pressureThreshold())
    @Published var pressureDeltaText: String = String(format: "%.2f", AppPreferences.pressureDelta())
    @Published var baselineWindowText: String = String(format: "%.0f", AppPreferences.baselineWindowMs())
    @Published var customFunctions: [CustomFunction] = AppPreferences.customFunctions()
    @Published var selectedFunctionID: CustomFunction.ID?

    func refresh() {
        language = AppPreferences.language()
        targetLanguage = AppPreferences.translationTargetLanguage()
        streamingEnabled = AppPreferences.translationStreamingEnabled()
        popupFontSize = Double(PopupFontPreferences.load())
        popupTooltipDelayText = String(format: "%.0f", AppPreferences.popupTooltipDelayMs())
        popupMaxWidthText = String(format: "%.0f", AppPreferences.popupMaxWidth())
        popupMaxHeightText = String(format: "%.0f", AppPreferences.popupMaxHeight())
        popupShortcut = AppPreferences.popupShortcut()
        apiKey = AppPreferences.apiKey()
        endpoint = AppPreferences.endpoint()
        pressureThresholdText = String(format: "%.2f", AppPreferences.pressureThreshold())
        pressureDeltaText = String(format: "%.2f", AppPreferences.pressureDelta())
        baselineWindowText = String(format: "%.0f", AppPreferences.baselineWindowMs())
        customFunctions = AppPreferences.customFunctions()
        if let selectedFunctionID, customFunctions.contains(where: { $0.id == selectedFunctionID }) {
            return
        }
        selectedFunctionID = customFunctions.first?.id
    }
}
