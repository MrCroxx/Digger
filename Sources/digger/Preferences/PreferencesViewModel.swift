import Foundation

@MainActor
final class PreferencesViewModel: ObservableObject {
    @Published var language: AppLanguage = AppPreferences.language()
    @Published var streamingEnabled: Bool = AppPreferences.translationStreamingEnabled()
    @Published var popupFontSize: Double = Double(PopupFontPreferences.load())
    @Published var popupOpacity: Double = Double(AppPreferences.popupOpacity())
    @Published var popupTooltipDelayText: String = String(format: "%.0f", AppPreferences.popupTooltipDelayMs())
    @Published var popupMaxWidthText: String = String(format: "%.0f", AppPreferences.popupMaxWidth())
    @Published var popupMaxHeightText: String = String(format: "%.0f", AppPreferences.popupMaxHeight())
    @Published var popupAutomaticSize = AppPreferences.popupAutomaticSize()
    @Published var popupShortcut: KeyboardShortcut = AppPreferences.popupShortcut()
    @Published var apiKey: String = AppPreferences.apiKey()
    @Published var endpoint: String = AppPreferences.endpoint()
    @Published var model: String = AppPreferences.model()
    @Published var thinkEffort: String = AppPreferences.thinkEffort()
    @Published var translationCacheMaxSizeGiBText: String = String(format: "%.2f", AppPreferences.translationCacheMaxSizeGiB())
    @Published var translationCacheTTLHoursText: String = String(format: "%.2f", AppPreferences.translationCacheTTLHours())
    @Published var customFunctions: [CustomFunction] = AppPreferences.customFunctions()
    @Published var systemPrompt: String = AppPreferences.systemPrompt()
    @Published var startOnLogin: Bool = AppPreferences.startOnLoginEnabled()
    @Published var selectedFunctionID: CustomFunction.ID?
    @Published var apiTestState: ApiTestState = .idle

    func refresh() {
        language = AppPreferences.language()
        streamingEnabled = AppPreferences.translationStreamingEnabled()
        popupFontSize = Double(PopupFontPreferences.load())
        popupOpacity = Double(AppPreferences.popupOpacity())
        popupTooltipDelayText = String(format: "%.0f", AppPreferences.popupTooltipDelayMs())
        popupMaxWidthText = String(format: "%.0f", AppPreferences.popupMaxWidth())
        popupMaxHeightText = String(format: "%.0f", AppPreferences.popupMaxHeight())
        popupAutomaticSize = AppPreferences.popupAutomaticSize()
        popupShortcut = AppPreferences.popupShortcut()
        apiKey = AppPreferences.apiKey()
        endpoint = AppPreferences.endpoint()
        model = AppPreferences.model()
        thinkEffort = AppPreferences.thinkEffort()
        translationCacheMaxSizeGiBText = String(format: "%.2f", AppPreferences.translationCacheMaxSizeGiB())
        translationCacheTTLHoursText = String(format: "%.2f", AppPreferences.translationCacheTTLHours())
        customFunctions = AppPreferences.customFunctions()
        systemPrompt = AppPreferences.systemPrompt()
        startOnLogin = AppPreferences.startOnLoginEnabled()
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
        let testedEndpoint = endpoint, testedModel = model, testedEffort = thinkEffort, testedKey = apiKey
        do {
            let output = try await OpenAITranslator.testConnection(
                apiKey: apiKeyText,
                endpoint: AppPreferences.resolvedEndpoint(endpoint),
                model: modelText,
                thinkEffort: thinkEffort
            )
            guard apiKey == testedKey, endpoint == testedEndpoint, model == testedModel, thinkEffort == testedEffort else {
                apiTestState = .idle; return
            }
            apiTestState = output.isEmpty ? .failure(UIStrings.Popup.emptyResult) : .success(UIStrings.Preferences.apiTestSuccess)
        } catch {
            guard apiKey == testedKey, endpoint == testedEndpoint, model == testedModel, thinkEffort == testedEffort else {
                apiTestState = .idle; return
            }
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
