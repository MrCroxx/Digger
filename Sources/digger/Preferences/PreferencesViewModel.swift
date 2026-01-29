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
    @Published var model: String = AppPreferences.model()
    @Published var pressureThresholdText: String = String(format: "%.2f", AppPreferences.pressureThreshold())
    @Published var pressureDeltaText: String = String(format: "%.2f", AppPreferences.pressureDelta())
    @Published var baselineWindowText: String = String(format: "%.0f", AppPreferences.baselineWindowMs())
    @Published var customFunctions: [CustomFunction] = AppPreferences.customFunctions()
    @Published var systemPrompt: String = AppPreferences.systemPrompt()
    @Published var selectedFunctionID: CustomFunction.ID?
    @Published var apiTestState: ApiTestState = .idle

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
        model = AppPreferences.model()
        pressureThresholdText = String(format: "%.2f", AppPreferences.pressureThreshold())
        pressureDeltaText = String(format: "%.2f", AppPreferences.pressureDelta())
        baselineWindowText = String(format: "%.0f", AppPreferences.baselineWindowMs())
        customFunctions = AppPreferences.customFunctions()
        systemPrompt = AppPreferences.systemPrompt()
        if let selectedFunctionID, customFunctions.contains(where: { $0.id == selectedFunctionID }) {
            return
        }
        selectedFunctionID = customFunctions.first?.id
    }

    func testAPI() async {
        let apiKeyText = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelText = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if apiKeyText.isEmpty {
            apiTestState = .failure(UIStrings.Preferences.apiTestMissingKey)
            return
        }
        if modelText.isEmpty {
            apiTestState = .failure(UIStrings.Preferences.apiTestMissingModel)
            return
        }

        apiTestState = .testing
        do {
            _ = try await OpenAITranslator.testConnection(
                apiKey: apiKeyText,
                endpoint: endpoint,
                model: modelText
            )
            apiTestState = .success(UIStrings.Preferences.apiTestSuccess)
        } catch {
            let message = UIStrings.Preferences.apiTestFailedPrefix + " " + error.localizedDescription
            apiTestState = .failure(message)
        }
    }
}

enum ApiTestState: Equatable {
    case idle
    case testing
    case success(String)
    case failure(String)
}
