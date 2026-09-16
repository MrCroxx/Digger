import AppKit
import Foundation

/// Owns one generation. Dismiss, stop, retry and a new selection all cancel its children.
@MainActor
final class PopupFunctionRunner {
    private var task: Task<Void, Never>?

    func run(text: String, forceAPI: Bool = false, anchorLocation: CGPoint? = nil) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let input = text // Leading indentation and trailing hard breaks are Markdown syntax.
        task?.cancel()
        let requestID = UUID()
        let started = ContinuousClock.now
        let functions = PopupFunction.availableFunctions()
        let anchor = anchorLocation ?? NSEvent.mouseLocation
        let streaming = AppPreferences.translationStreamingEnabled()
        let translator = OpenAITranslator()
        selectionPopup.onStop = { [weak self] in self?.task?.cancel() }
        selectionPopup.showLoading(original: input, near: anchor, requestID: requestID, functions: functions)
        task = Task {
            await withTaskGroup(of: Void.self) { group in
                for function in functions {
                    group.addTask {
                        await Self.execute(function: function, input: input, translator: translator,
                                           requestID: requestID, anchor: anchor, streaming: streaming, forceAPI: forceAPI, started: started)
                    }
                }
            }
        }
    }

    private static func execute(function: PopupFunction, input: String, translator: OpenAITranslator?,
                                requestID: UUID, anchor: CGPoint, streaming: Bool, forceAPI: Bool,
                                started: ContinuousClock.Instant) async {
        // Debug timings contain action metadata and counts, never selections, answers, or keys.
        func trace(_ stage: String) {
            #if DEBUG
            let elapsed = started.duration(to: .now).components
            let milliseconds = elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000
            print("[Digger timing] request=\(requestID.uuidString.prefix(8)) action=\(function.title.debugDescription) elapsed_ms=\(milliseconds) \(stage)")
            #endif
        }
        func publish(_ text: String, final: Bool, cached: Bool = false, error: Bool = false) {
            guard !Task.isCancelled else { return }
            selectionPopup.updateResult(text, for: requestID, functionID: function.id, near: anchor,
                                        isFinal: final, isCacheHit: cached, isError: error)
        }
        guard !Task.isCancelled else { return }
        guard let translator else {
            publish(localized("Check your API key and endpoint in Settings.", "请在设置中检查 API 密钥和地址。", "設定で API キーとエンドポイントを確認してください。"), final: true, error: true); return
        }
        guard !function.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            publish(UIStrings.Popup.emptyPrompt, final: true, error: true); return
        }
        trace("start streaming=\(streaming) bypass_cache=\(forceAPI)")
        do {
            if streaming {
                let result = try await translator.runPromptStreamWithCacheInfo(function.prompt, text: input, useCache: !forceAPI)
                trace("stream_ready cache_hit=\(result.isCacheHit)")
                var output = ""
                for try await delta in result.stream {
                    try Task.checkCancellation()
                    if output.isEmpty && !delta.isEmpty { trace("first_text") }
                    output += delta
                    // The model buffers visual updates on its own clock. Forward every
                    // delta so a short chunk cannot get stranded during a network pause.
                    publish(output, final: false, cached: result.isCacheHit)
                }
                try Task.checkCancellation()
                publish(output.isEmpty ? UIStrings.Popup.emptyResult : output, final: true, cached: result.isCacheHit)
                trace("complete chars=\(output.count) cache_hit=\(result.isCacheHit)")
            } else {
                let result = try await translator.runPromptWithCacheInfo(function.prompt, text: input, useCache: !forceAPI)
                try Task.checkCancellation()
                publish(result.output.isEmpty ? UIStrings.Popup.emptyResult : result.output, final: true, cached: result.isCacheHit)
                trace("complete chars=\(result.output.count) cache_hit=\(result.isCacheHit)")
            }
        } catch is CancellationError {
            trace("cancelled")
            // The model is stopped by the owner; never replace partial text with an error.
        } catch {
            trace("failed")
            publish(UIStrings.Translation.failed + "\n\n" + error.localizedDescription, final: true, error: true)
        }
    }
}
