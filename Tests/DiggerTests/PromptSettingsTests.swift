import Foundation
import Testing
@testable import digger

struct PromptSettingsTests {
    @Test func defaultsOnlyRunTranslationAndNewPromptsAreEnabled() {
        let defaults = AppPreferences.defaultCustomFunctions
        #expect(defaults.count == 2)
        #expect(PopupFunction.availableFunctions(from: defaults).map(\.title) == ["Translation"])
        #expect(defaults.first(where: { $0.title == "Summary" })?.isEnabled == false)
        #expect(CustomFunction(title: "Rewrite", prompt: "Rewrite").isEnabled)
    }

    @Test func legacyConfigurationPreservesContentAndDisablesOnlyDefaultSummary() throws {
        let original = [
            CustomFunction(title: "Translation", prompt: "My translation instructions"),
            CustomFunction(title: "Summary", prompt: CustomFunction.defaultSummaryPrompt),
            CustomFunction(id: CustomFunction.defaultSummaryID, title: "摘要", prompt: "Edited summary"),
            CustomFunction(title: "Summary", prompt: "My custom summary instructions"),
            CustomFunction(title: "Rewrite", prompt: "Rewrite precisely")
        ]
        let legacy = original.map { ["id": $0.id.uuidString, "title": $0.title, "prompt": $0.prompt] }
        let decoded = try JSONDecoder().decode([CustomFunction].self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.map(\.id) == original.map(\.id))
        #expect(decoded.map(\.title) == original.map(\.title))
        #expect(decoded.map(\.prompt) == original.map(\.prompt))
        #expect(decoded.map(\.isEnabled) == [true, false, false, true, true])
    }

    @Test func explicitTogglesSurviveSavingAndControlExecutionOrder() throws {
        var functions = AppPreferences.defaultCustomFunctions
        functions[0].isEnabled = false
        functions[1].isEnabled = true
        functions.append(CustomFunction(title: "Rewrite", prompt: "Rewrite"))
        let saved = try JSONEncoder().encode(functions)
        let loaded = try JSONDecoder().decode([CustomFunction].self, from: saved)
        #expect(loaded == functions)
        let runnable = PopupFunction.availableFunctions(from: loaded)
        #expect(runnable.map(\.id) == [functions[1].id, functions[2].id])
        #expect(runnable.map(\.prompt) == [functions[1].prompt, functions[2].prompt])
        for index in functions.indices { functions[index].isEnabled = false }
        #expect(PopupFunction.availableFunctions(from: functions).isEmpty)
    }
}
