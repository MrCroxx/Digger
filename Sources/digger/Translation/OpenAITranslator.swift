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
    private let model: String
    private let endpoint: String
    private let thinkEffort: String
    private let systemPrompt: String
    private let cache: TranslationDiskCache

    init?(apiKey: String = AppPreferences.apiKey(), endpoint: String = AppPreferences.endpointOrDefault(),
          model: String = AppPreferences.model(), thinkEffort: String = AppPreferences.thinkEffort(),
          systemPrompt: String = AppPreferences.systemPrompt(), cache: TranslationDiskCache = .shared) {
        guard let configuration = Self.configuration(apiKey: apiKey, endpoint: endpoint) else { return nil }
        client = OpenAI(configuration: configuration)
        self.model = model
        self.endpoint = endpoint
        self.thinkEffort = thinkEffort
        self.systemPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        self.cache = cache
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
            throw apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? TestError.missingApiKey : TestError.invalidEndpoint
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

    static func configuration(apiKey: String, endpoint: String) -> OpenAI.Configuration? {
        let token = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            return nil
        }

        guard let parsed = URLComponents(string: AppPreferences.resolvedEndpoint(endpoint)),
              let scheme = parsed.scheme, ["http", "https"].contains(scheme),
              let host = parsed.host, !host.isEmpty,
              parsed.user == nil, parsed.password == nil,
              parsed.query == nil, parsed.fragment == nil else { return nil }
        let basePath = parsed.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let port = parsed.port ?? (scheme == "http" ? 80 : 443)

        return OpenAI.Configuration(
            token: token,
            host: host,
            port: port,
            scheme: scheme,
            basePath: basePath.isEmpty ? "/v1" : "/" + basePath,
            parsingOptions: .relaxed
        )
    }

    private enum TestError: LocalizedError {
        case missingApiKey
        case missingModel
        case invalidEndpoint

        var errorDescription: String? {
            switch self {
            case .missingApiKey:
                return UIStrings.Preferences.apiTestMissingKey
            case .missingModel:
                return UIStrings.Preferences.apiTestMissingModel
            case .invalidEndpoint:
                return localized("Enter a valid HTTP or HTTPS API endpoint.", "请输入有效的 HTTP 或 HTTPS API 地址。", "有効な HTTP または HTTPS の API エンドポイントを入力してください。")
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
        if useCache, let cachedOutput = await cache.cachedOutput(for: cacheKey) {
            return PromptResult(output: cachedOutput, isCacheHit: true)
        }
        let result = try await client.chats(query: query)
        let output = result.choices.first?.message.content ?? ""
        try Task.checkCancellation()
        await cache.storeOutput(output, for: cacheKey)
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
        if useCache, let cachedOutput = await cache.cachedOutput(for: cacheKey) {
            return PromptStreamResult(
                stream: Self.singleValueStream(output: cachedOutput),
                isCacheHit: true
            )
        }

        let stream: AsyncThrowingStream<ChatStreamResult, Error> = client.chatsStream(query: query)
        let outputStream = AsyncThrowingStream<String, Error> { continuation in
            let worker = Task {
                var accumulatedOutput = ""
                do {
                    for try await result in stream {
                        try Task.checkCancellation()
                        for choice in result.choices {
                            if let delta = choice.delta.content, !delta.isEmpty {
                                accumulatedOutput += delta
                                continuation.yield(delta)
                            }
                        }
                    }
                    try Task.checkCancellation()
                    await cache.storeOutput(accumulatedOutput, for: cacheKey)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in worker.cancel() }
        }
        return PromptStreamResult(stream: outputStream, isCacheHit: false)
    }

    private func makeQueryAndCacheKey(
        prompt: String,
        text: String
    ) -> (query: ChatQuery, cacheKey: TranslationDiskCache.RequestKey) {
        let reasoningEffort = Self.reasoningEffort(thinkEffort)
        let effectivePrompt = PromptTemplates.preservingMarkdown(prompt)
        var messages: [ChatQuery.ChatCompletionMessageParam] = []
        if !systemPrompt.isEmpty {
            messages.append(.system(.init(content: .textContent(systemPrompt))))
        }
        messages.append(.system(.init(content: .textContent(effectivePrompt))))
        messages.append(.user(.init(content: .string(text))))

        let query = ChatQuery(
            messages: messages,
            model: model,
            reasoningEffort: reasoningEffort,
            temperature: reasoningEffort == nil ? 0.2 : nil
        )
        let cacheKey = TranslationDiskCache.makeRequestKey(
            input: text,
            prompt: effectivePrompt,
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
