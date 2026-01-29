import AppKit
import Foundation

final class PopupFunctionRunner: @unchecked Sendable {
    func run(text: String) async {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }
        guard let location = currentMouseLocation() else {
            return
        }
        let requestID = UUID()
        let functions = PopupFunction.availableFunctions()
        let anchor = PopupAnchor(point: location)
        let context = PopupRequestContext(requestID: requestID, anchor: anchor, functions: functions)
        await showLoading(original: trimmedText, context: context)

        let apiKey = AppPreferences.apiKey().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            await publishResultForAll(UIStrings.Translation.missingApiKey, context: context, shouldLog: true)
            return
        }

        await withTaskGroup(of: Void.self) { group in
            for function in functions {
                group.addTask { [self] in
                    await run(function: function, text: trimmedText, context: context)
                }
            }
        }
    }

    private func run(function: PopupFunction, text: String, context: PopupRequestContext) async {
        guard let translator = OpenAITranslator() else {
            await publishResult(UIStrings.Translation.missingApiKey, for: function, context: context, isFinal: true, shouldLog: true)
            return
        }
        let trimmedPrompt = function.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            await publishResult(UIStrings.Popup.emptyPrompt, for: function, context: context, isFinal: true, shouldLog: false)
            return
        }

        if AppPreferences.translationStreamingEnabled() {
            await runStreaming(translator: translator, prompt: trimmedPrompt, text: text, function: function, context: context)
        } else {
            await runNonStreaming(translator: translator, prompt: trimmedPrompt, text: text, function: function, context: context)
        }
    }

    private func runStreaming(
        translator: OpenAITranslator,
        prompt: String,
        text: String,
        function: PopupFunction,
        context: PopupRequestContext
    ) async {
        do {
            let stream = try await translator.runPromptStream(prompt, text: text)
            var accumulated = ""
            var pending = ""
            let updateInterval: TimeInterval = 0.02
            let minFlushCharacters = 48
            var lastUpdate = ProcessInfo.processInfo.systemUptime
            await markStreamingStarted(for: function, context: context)
            for try await delta in stream {
                guard !delta.isEmpty else {
                    continue
                }
                pending += delta
                let now = ProcessInfo.processInfo.systemUptime
                if pending.count >= minFlushCharacters || now - lastUpdate >= updateInterval {
                    accumulated += pending
                    pending = ""
                    lastUpdate = now
                    await publishProgress(accumulated, for: function, context: context)
                }
            }
            if !pending.isEmpty {
                accumulated += pending
                pending = ""
                await publishProgress(accumulated, for: function, context: context)
            }
            let trimmed = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
            let resultText = trimmed.isEmpty ? UIStrings.Popup.emptyResult : trimmed
            await publishResult(resultText, for: function, context: context, isFinal: true, shouldLog: true)
        } catch {
            let resultText = UIStrings.Translation.failed
            await publishResult(resultText, for: function, context: context, isFinal: true, shouldLog: true)
        }
    }

    private func runNonStreaming(
        translator: OpenAITranslator,
        prompt: String,
        text: String,
        function: PopupFunction,
        context: PopupRequestContext
    ) async {
        let resultText: String
        do {
            let result = try await translator.runPrompt(prompt, text: text)
            resultText = result.isEmpty ? UIStrings.Popup.emptyResult : result
        } catch {
            resultText = UIStrings.Translation.failed
        }
        await publishResult(resultText, for: function, context: context, isFinal: true, shouldLog: true)
    }

    private func showLoading(original: String, context: PopupRequestContext) async {
        await MainActor.run {
            forceClickSelectionPopup.showLoading(
                original: original,
                near: context.anchor.point,
                requestID: context.requestID,
                functions: context.functions
            )
        }
    }

    private func markStreamingStarted(for function: PopupFunction, context: PopupRequestContext) async {
        await MainActor.run {
            forceClickSelectionPopup.markStreamingStarted(
                for: context.requestID,
                functionID: function.id,
                near: context.anchor.point
            )
        }
    }

    private func publishResultForAll(_ text: String, context: PopupRequestContext, shouldLog: Bool) async {
        for function in context.functions {
            await publishResult(text, for: function, context: context, isFinal: true, shouldLog: shouldLog)
        }
    }

    private func publishProgress(_ text: String, for function: PopupFunction, context: PopupRequestContext) async {
        await updatePopupResult(text, context: context, functionID: function.id, isFinal: false)
    }

    private func publishResult(
        _ text: String,
        for function: PopupFunction,
        context: PopupRequestContext,
        isFinal: Bool,
        shouldLog: Bool
    ) async {
        if shouldLog {
            print("\(function.title): \(text)")
        }
        await updatePopupResult(text, context: context, functionID: function.id, isFinal: isFinal)
    }

    private func updatePopupResult(
        _ text: String,
        context: PopupRequestContext,
        functionID: UUID,
        isFinal: Bool
    ) async {
        await MainActor.run {
            forceClickSelectionPopup.updateResult(
                text,
                for: context.requestID,
                functionID: functionID,
                near: context.anchor.point,
                isFinal: isFinal
            )
        }
    }

    private func currentMouseLocation() -> CGPoint? {
        NSEvent.mouseLocation
    }
}

private struct PopupAnchor: Sendable {
    let x: Double
    let y: Double

    init(point: CGPoint) {
        x = Double(point.x)
        y = Double(point.y)
    }

    var point: CGPoint {
        CGPoint(x: x, y: y)
    }
}

private struct PopupRequestContext: Sendable {
    let requestID: UUID
    let anchor: PopupAnchor
    let functions: [PopupFunction]
}
