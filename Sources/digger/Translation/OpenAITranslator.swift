import Foundation
import OpenAI

actor OpenAITranslator {
    struct PromptResult: Sendable {
        let output: String
        let isCacheHit: Bool
    }

    struct PromptStreamResult: Sendable {
        let stream: AsyncThrowingStream<String, Error>
        let isCacheHit: Bool
    }

    private let client: OpenAI

    init?() {
        guard let configuration = Self.configuration(
            apiKey: AppPreferences.apiKey(),
            endpoint: AppPreferences.endpointOrDefault()
        ) else {
            return nil
        }

        client = OpenAI(configuration: configuration)
    }

    static func testConnection(
        apiKey: String,
        endpoint: String,
        model: String,
        thinkEffort: String
    ) async throws -> String {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            throw TestError.missingModel
        }
        guard let configuration = configuration(apiKey: apiKey, endpoint: endpoint) else {
            throw TestError.missingApiKey
        }
        let client = OpenAI(configuration: configuration)
        let reasoningEffort = reasoningEffort(thinkEffort)
        let query = ChatQuery(
            messages: [.user(.init(content: .string("Reply with OK.")))],
            model: trimmedModel,
            reasoningEffort: reasoningEffort,
            temperature: reasoningEffort == nil ? 0 : nil
        )
        let result = try await client.chats(query: query)
        return result.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func configuration(apiKey: String, endpoint: String) -> OpenAI.Configuration? {
        let token = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            return nil
        }

        var host = "api.openai.com"
        var basePath = "/v1"
        var port = 443
        var scheme = "https"
        let endpointText = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !endpointText.isEmpty,
           let endpoint = URL(string: endpointText) {
            if let endpointHost = endpoint.host {
                host = endpointHost
            }
            if !endpoint.path.isEmpty {
                basePath = endpoint.path
            }
            if let endpointScheme = endpoint.scheme {
                scheme = endpointScheme
            }
            if let endpointPort = endpoint.port {
                port = endpointPort
            }
        }

        return OpenAI.Configuration(
            token: token,
            host: host,
            port: port,
            scheme: scheme,
            basePath: basePath,
            parsingOptions: .relaxed
        )
    }

    private enum TestError: LocalizedError {
        case missingApiKey
        case missingModel

        var errorDescription: String? {
            switch self {
            case .missingApiKey:
                return "OPENAI_API_KEY is not set"
            case .missingModel:
                return "OPENAI_MODEL is not set"
            }
        }
    }

    func translate(_ text: String) async throws -> String {
        let prompt = PromptTemplates.defaultTranslationPrompt
        return try await runPrompt(prompt, text: text)
    }

    func translateStream(_ text: String) async throws -> AsyncThrowingStream<String, Error> {
        let prompt = PromptTemplates.defaultTranslationPrompt
        return try await runPromptStream(prompt, text: text)
    }

    func runPrompt(_ prompt: String, text: String) async throws -> String {
        let result = try await runPromptWithCacheInfo(prompt, text: text)
        return result.output
    }

    func runPromptWithCacheInfo(
        _ prompt: String,
        text: String,
        useCache: Bool = true
    ) async throws -> PromptResult {
        let (query, cacheKey) = makeQueryAndCacheKey(prompt: prompt, text: text)
        if useCache, let cachedOutput = await TranslationDiskCache.shared.cachedOutput(for: cacheKey) {
            return PromptResult(output: cachedOutput, isCacheHit: true)
        }
        let result = try await client.chats(query: query)
        let output = result.choices.first?.message.content?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        await TranslationDiskCache.shared.storeOutput(output, for: cacheKey)
        return PromptResult(output: output, isCacheHit: false)
    }

    func runPromptStream(_ prompt: String, text: String) async throws -> AsyncThrowingStream<String, Error> {
        let result = try await runPromptStreamWithCacheInfo(prompt, text: text)
        return result.stream
    }

    func runPromptStreamWithCacheInfo(
        _ prompt: String,
        text: String,
        useCache: Bool = true
    ) async throws -> PromptStreamResult {
        let (query, cacheKey) = makeQueryAndCacheKey(prompt: prompt, text: text)
        if useCache, let cachedOutput = await TranslationDiskCache.shared.cachedOutput(for: cacheKey) {
            return PromptStreamResult(
                stream: Self.singleValueStream(output: cachedOutput),
                isCacheHit: true
            )
        }

        let stream: AsyncThrowingStream<ChatStreamResult, Error> = client.chatsStream(query: query)
        let outputStream = AsyncThrowingStream<String, Error> { continuation in
            Task {
                var accumulatedOutput = ""
                do {
                    for try await result in stream {
                        for choice in result.choices {
                            if let delta = choice.delta.content, !delta.isEmpty {
                                accumulatedOutput += delta
                                continuation.yield(delta)
                            }
                        }
                    }
                    let output = accumulatedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                    await TranslationDiskCache.shared.storeOutput(output, for: cacheKey)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
        return PromptStreamResult(stream: outputStream, isCacheHit: false)
    }

    private func makeQueryAndCacheKey(
        prompt: String,
        text: String
    ) -> (query: ChatQuery, cacheKey: TranslationDiskCache.RequestKey) {
        let model = AppPreferences.model()
        let endpoint = AppPreferences.endpointOrDefault()
        let thinkEffort = AppPreferences.thinkEffort()
        let reasoningEffort = Self.reasoningEffort(thinkEffort)
        let systemPrompt = AppPreferences.systemPrompt().trimmingCharacters(in: .whitespacesAndNewlines)
        var messages: [ChatQuery.ChatCompletionMessageParam] = []
        if !systemPrompt.isEmpty {
            messages.append(.system(.init(content: .textContent(systemPrompt))))
        }
        messages.append(.system(.init(content: .textContent(prompt))))
        messages.append(.user(.init(content: .string(text))))

        let query = ChatQuery(
            messages: messages,
            model: model,
            reasoningEffort: reasoningEffort,
            temperature: reasoningEffort == nil ? 0.2 : nil
        )
        let cacheKey = TranslationDiskCache.makeRequestKey(
            input: text,
            prompt: prompt,
            systemPrompt: systemPrompt,
            model: model,
            endpoint: endpoint,
            thinkEffort: thinkEffort
        )
        return (query: query, cacheKey: cacheKey)
    }

    private static func reasoningEffort(_ value: String) -> ChatQuery.ReasoningEffort? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }
        switch value.lowercased() {
        case "none": return ChatQuery.ReasoningEffort.none
        case "minimal": return .minimal
        case "low": return .low
        case "medium": return .medium
        case "high": return .high
        default: return .customValue(value)
        }
    }

    private static func singleValueStream(output: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            if !output.isEmpty {
                continuation.yield(output)
            }
            continuation.finish()
        }
    }
}
