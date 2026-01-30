import Foundation
import OpenAI

actor OpenAITranslator {
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

    static func testConnection(apiKey: String, endpoint: String, model: String) async throws -> String {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            throw TestError.missingModel
        }
        guard let configuration = configuration(apiKey: apiKey, endpoint: endpoint) else {
            throw TestError.missingApiKey
        }
        let client = OpenAI(configuration: configuration)
        let query = ChatQuery(
            messages: [.user(.init(content: .string("Reply with OK.")))],
            model: trimmedModel,
            temperature: 0
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
        let prompt = PromptTemplates.translation(for: AppPreferences.translationTargetLanguage())
        return try await runPrompt(prompt, text: text)
    }

    func translateStream(_ text: String) async throws -> AsyncThrowingStream<String, Error> {
        let prompt = PromptTemplates.translation(for: AppPreferences.translationTargetLanguage())
        return try await runPromptStream(prompt, text: text)
    }

    func runPrompt(_ prompt: String, text: String) async throws -> String {
        let model = AppPreferences.model()
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
            temperature: 0.2
        )
        let result = try await client.chats(query: query)
        return result.choices.first?.message.content?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
    }

    func runPromptStream(_ prompt: String, text: String) async throws -> AsyncThrowingStream<String, Error> {
        let model = AppPreferences.model()
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
            temperature: 0.2
        )
        let stream: AsyncThrowingStream<ChatStreamResult, Error> = client.chatsStream(query: query)
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await result in stream {
                        for choice in result.choices {
                            if let delta = choice.delta.content, !delta.isEmpty {
                                continuation.yield(delta)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
