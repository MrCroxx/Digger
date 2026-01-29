import Foundation
import OpenAI

actor OpenAITranslator {
    private let client: OpenAI

    init?() {
        let token = AppPreferences.apiKey()
        guard !token.isEmpty else {
            return nil
        }

        var host = "api.openai.com"
        var basePath = "/v1"
        var port = 443
        var scheme = "https"
        let endpointText = AppPreferences.endpoint()
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

        let configuration = OpenAI.Configuration(
            token: token,
            host: host,
            port: port,
            scheme: scheme,
            basePath: basePath,
            parsingOptions: .relaxed
        )

        client = OpenAI(configuration: configuration)
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
        let query = ChatQuery(
            messages: [
                .system(.init(content: .textContent(prompt))),
                .user(.init(content: .string(text)))
            ],
            model: model,
            temperature: 0.2
        )
        let result = try await client.chats(query: query)
        return result.choices.first?.message.content?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
    }

    func runPromptStream(_ prompt: String, text: String) async throws -> AsyncThrowingStream<String, Error> {
        let model = AppPreferences.model()
        let query = ChatQuery(
            messages: [
                .system(.init(content: .textContent(prompt))),
                .user(.init(content: .string(text)))
            ],
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
