import AppKit
import Foundation

final class PopupFunctionRunner: @unchecked Sendable {
    func run(
        text: String,
        originalText: String? = nil,
        forceAPI: Bool = false,
        anchorLocation: CGPoint? = nil
    ) async {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }
        let trimmedOriginalText = (originalText ?? text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOriginalText.isEmpty else {
            return
        }
        let resolvedLocation = anchorLocation ?? currentMouseLocation()
        guard let location = resolvedLocation else {
            return
        }
        let requestID = UUID()
        let functions = PopupFunction.availableFunctions()
        let dictionaryFunctions = functions.filter { $0.isSystemDictionary }
        let aiFunctions = functions.filter { !$0.isSystemDictionary }
        let anchor = PopupAnchor(point: location)
        let context = PopupRequestContext(requestID: requestID, anchor: anchor, functions: functions)
        await showLoading(original: trimmedOriginalText, requestText: trimmedText, context: context)

        await withTaskGroup(of: Void.self) { group in
            for function in dictionaryFunctions {
                group.addTask { [self] in
                    await runSystemDictionary(function: function, text: trimmedText, context: context)
                }
            }
            guard !aiFunctions.isEmpty else {
                return
            }
            let apiKey = AppPreferences.apiKey().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !apiKey.isEmpty else {
                for function in aiFunctions {
                    group.addTask { [self] in
                        await publishResult(
                            UIStrings.Translation.missingApiKey,
                            for: function,
                            context: context,
                            isFinal: true,
                            shouldLog: true,
                            isCacheHit: false
                        )
                    }
                }
                return
            }
            for function in aiFunctions {
                group.addTask { [self] in
                    await run(function: function, text: trimmedText, context: context, forceAPI: forceAPI)
                }
            }
        }
    }

    private func runSystemDictionary(function: PopupFunction, text: String, context: PopupRequestContext) async {
        guard let result = SystemDictionaryService.lookup(text: text) else {
            await publishResult(
                UIStrings.Popup.dictionaryNoResult,
                for: function,
                context: context,
                isFinal: true,
                shouldLog: false,
                isCacheHit: false
            )
            return
        }
        await updatePopupMarkdownResult(
            markdown: result.markdownText,
            plainText: result.plainText,
            context: context,
            functionID: function.id,
            isFinal: true,
            isCacheHit: false
        )
    }

    private func run(
        function: PopupFunction,
        text: String,
        context: PopupRequestContext,
        forceAPI: Bool
    ) async {
        guard let translator = OpenAITranslator() else {
            await publishResult(
                UIStrings.Translation.missingApiKey,
                for: function,
                context: context,
                isFinal: true,
                shouldLog: true,
                isCacheHit: false
            )
            return
        }
        let trimmedPrompt = function.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            await publishResult(
                UIStrings.Popup.emptyPrompt,
                for: function,
                context: context,
                isFinal: true,
                shouldLog: false,
                isCacheHit: false
            )
            return
        }

        if AppPreferences.translationStreamingEnabled() {
            await runStreaming(
                translator: translator,
                prompt: trimmedPrompt,
                text: text,
                function: function,
                context: context,
                forceAPI: forceAPI
            )
        } else {
            await runNonStreaming(
                translator: translator,
                prompt: trimmedPrompt,
                text: text,
                function: function,
                context: context,
                forceAPI: forceAPI
            )
        }
    }

    private func runStreaming(
        translator: OpenAITranslator,
        prompt: String,
        text: String,
        function: PopupFunction,
        context: PopupRequestContext,
        forceAPI: Bool
    ) async {
        do {
            let streamResult = try await translator.runPromptStreamWithCacheInfo(
                prompt,
                text: text,
                useCache: !forceAPI
            )
            if streamResult.isCacheHit {
                var cachedOutput = ""
                for try await delta in streamResult.stream {
                    guard !delta.isEmpty else {
                        continue
                    }
                    cachedOutput += delta
                }
                let trimmed = cachedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                let resultText = trimmed.isEmpty ? UIStrings.Popup.emptyResult : trimmed
                await publishResult(
                    resultText,
                    for: function,
                    context: context,
                    isFinal: true,
                    shouldLog: true,
                    isCacheHit: true
                )
                return
            }

            let stream = streamResult.stream
            var accumulated = ""
            var pending = ""
            let updateInterval: TimeInterval = 0.033
            let minFlushCharacters = 72
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
                    await publishProgress(accumulated, for: function, context: context, isCacheHit: false)
                }
            }
            if !pending.isEmpty {
                accumulated += pending
                pending = ""
                await publishProgress(accumulated, for: function, context: context, isCacheHit: false)
            }
            let trimmed = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
            let resultText = trimmed.isEmpty ? UIStrings.Popup.emptyResult : trimmed
            await publishResult(
                resultText,
                for: function,
                context: context,
                isFinal: true,
                shouldLog: true,
                isCacheHit: false
            )
        } catch {
            let resultText = UIStrings.Translation.failed
            await publishResult(
                resultText,
                for: function,
                context: context,
                isFinal: true,
                shouldLog: true,
                isCacheHit: false
            )
        }
    }

    private func runNonStreaming(
        translator: OpenAITranslator,
        prompt: String,
        text: String,
        function: PopupFunction,
        context: PopupRequestContext,
        forceAPI: Bool
    ) async {
        let resultText: String
        var isCacheHit = false
        do {
            let result = try await translator.runPromptWithCacheInfo(
                prompt,
                text: text,
                useCache: !forceAPI
            )
            isCacheHit = result.isCacheHit
            resultText = result.output.isEmpty ? UIStrings.Popup.emptyResult : result.output
        } catch {
            resultText = UIStrings.Translation.failed
            isCacheHit = false
        }
        await publishResult(
            resultText,
            for: function,
            context: context,
            isFinal: true,
            shouldLog: true,
            isCacheHit: isCacheHit
        )
    }

    private func showLoading(original: String, requestText: String, context: PopupRequestContext) async {
        await MainActor.run {
            forceClickSelectionPopup.showLoading(
                original: original,
                requestText: requestText,
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

    private func publishProgress(
        _ text: String,
        for function: PopupFunction,
        context: PopupRequestContext,
        isCacheHit: Bool
    ) async {
        await updatePopupResult(
            text,
            context: context,
            functionID: function.id,
            isFinal: false,
            isCacheHit: isCacheHit
        )
    }

    private func publishResult(
        _ text: String,
        for function: PopupFunction,
        context: PopupRequestContext,
        isFinal: Bool,
        shouldLog: Bool,
        isCacheHit: Bool
    ) async {
        if shouldLog {
            print("\(function.title): \(text)")
        }
        await updatePopupResult(
            text,
            context: context,
            functionID: function.id,
            isFinal: isFinal,
            isCacheHit: isCacheHit
        )
    }

    private func updatePopupResult(
        _ text: String,
        context: PopupRequestContext,
        functionID: UUID,
        isFinal: Bool,
        isCacheHit: Bool
    ) async {
        await MainActor.run {
            forceClickSelectionPopup.updateResult(
                text,
                for: context.requestID,
                functionID: functionID,
                near: context.anchor.point,
                isFinal: isFinal,
                isCacheHit: isCacheHit
            )
        }
    }

    private func updatePopupMarkdownResult(
        markdown: String,
        plainText: String,
        context: PopupRequestContext,
        functionID: UUID,
        isFinal: Bool,
        isCacheHit: Bool
    ) async {
        await MainActor.run {
            forceClickSelectionPopup.updateMarkdownResult(
                markdown: markdown,
                plainText: plainText,
                for: context.requestID,
                functionID: functionID,
                near: context.anchor.point,
                isFinal: isFinal,
                isCacheHit: isCacheHit
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
