import Foundation
import Testing
@testable import digger

struct EndpointTests {
    @Test func validatesAndNormalizesEndpoint() throws {
        let http = try #require(OpenAITranslator.configuration(apiKey: "fixture", endpoint: "http://localhost/custom/v1/"))
        #expect(OpenAITranslator.configuration(apiKey: "fixture", endpoint: "https://example.com")?.basePath == "/v1")
        #expect(http.port == 80)
        #expect(http.basePath == "/custom/v1")
        let local = try #require(OpenAITranslator.configuration(apiKey: "fixture", endpoint: "http://127.0.0.1:12345/v1"))
        #expect(local.port == 12345)
        #expect(OpenAITranslator.configuration(apiKey: "fixture", endpoint: "not a url") == nil)
        #expect(OpenAITranslator.configuration(apiKey: "fixture", endpoint: "file:///tmp/data") == nil)
        #expect(OpenAITranslator.configuration(apiKey: "fixture", endpoint: "https://user:pass@example.com/v1") == nil)
        #expect(OpenAITranslator.configuration(apiKey: "", endpoint: "https://example.com") == nil)
    }
}

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["DIGGER_TEST_ENDPOINT"] != nil))
struct TransportTests {
    let endpoint = ProcessInfo.processInfo.environment["DIGGER_TEST_ENDPOINT"] ?? ""
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("digger-tests-" + UUID().uuidString)

    func translator(model: String = "fixture", effort: String = "") throws -> OpenAITranslator {
        try #require(OpenAITranslator(apiKey: "test-only", endpoint: endpoint, model: model, thinkEffort: effort,
                                      systemPrompt: "Fixture system", cache: TranslationDiskCache(directory: directory)))
    }

    @Test func completionAndDiskCacheRoundTrip() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = try translator(effort: "high")
        let legacyKey = TranslationDiskCache.makeRequestKey(input: "Fixture selection", prompt: "Fixture prompt",
            systemPrompt: "Fixture system", model: "fixture", endpoint: endpoint, thinkEffort: "high")
        await TranslationDiskCache(directory: directory).storeOutput("Legacy unformatted result", for: legacyKey)
        let first = try await client.runPromptWithCacheInfo("Fixture prompt", text: "Fixture selection")
        #expect(first.output == "Hello 世界")
        #expect(!first.isCacheHit)
        let next = try await client.runPromptWithCacheInfo("Fixture prompt", text: "Fixture selection")
        #expect(next.isCacheHit)
        #expect(next.output == first.output)
    }

    @Test func streamingRoundTrip() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = try translator()
        let result = try await client.runPromptStreamWithCacheInfo("Fixture prompt", text: "Fixture selection", useCache: false)
        var output = ""
        for try await delta in result.stream { output += delta }
        #expect(output == "Hello 世界")
        let cached = try await client.runPromptWithCacheInfo("Fixture prompt", text: "Fixture selection")
        #expect(cached.isCacheHit)
        #expect(cached.output == output)
    }

    @Test @MainActor func markdownStreamAndCachePreserveExactSource() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = try translator(model: "markdown")
        let input = "    let source = 1\n\n# Source\n"
        let result = try await client.runPromptStreamWithCacheInfo("Fixture prompt", text: input, useCache: false)
        let model = ResultModel(), id = UUID()
        let function = PopupFunction(id: UUID(), title: "Translate", prompt: "Fixture prompt", isTranslation: true)
        model.begin(original: input, requestID: id, functions: [function])
        var output = "", snapshots = 0
        for try await delta in result.stream {
            output += delta
            model.update(output, requestID: id, functionID: function.id, phase: .streaming)
            snapshots += 1
        }
        #expect(snapshots > 3)
        #expect(output.hasPrefix("    let value = 1\n"))
        #expect(output.hasSuffix("hard break  \n"))
        #expect(model.sections[0].markdown.renderHTML().contains("<table>"))
        #expect(model.sections[0].markdown.renderHTML().contains("<strong>bold</strong>"))
        #expect(model.sections[0].text == output)
        #expect(model.original == input)
        let cached = try await client.runPromptWithCacheInfo("Fixture prompt", text: input)
        #expect(cached.isCacheHit)
        #expect(cached.output == output)
        let complete = try await client.runPromptWithCacheInfo("Fixture prompt", text: input, useCache: false)
        #expect(complete.output == output)
    }

    @Test func cancellationStopsNetworkAndDoesNotCachePartialOutput() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = try translator(model: "slow")
        let stream = try await client.runPromptStreamWithCacheInfo("Fixture prompt", text: "Fixture selection", useCache: false)
        let consumer = Task {
            for try await _ in stream.stream { try Task.checkCancellation() }
        }
        try await Task.sleep(for: .milliseconds(300))
        consumer.cancel()
        _ = await consumer.result
        try await Task.sleep(for: .milliseconds(500))
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        #expect(files.isEmpty)
        let (data, _) = try await URLSession.shared.data(from: URL(string: endpoint + "/status")!)
        let status = try JSONDecoder().decode(FixtureStatus.self, from: data)
        #expect(status.cancelled > 0)
    }

    @Test func serverErrorsReachTheCaller() async throws {
        let client = try translator(model: "error")
        await #expect(throws: (any Error).self) {
            _ = try await client.runPromptWithCacheInfo("Fixture prompt", text: "Fixture selection", useCache: false)
        }
    }
}

private struct FixtureStatus: Decodable { let cancelled: Int }
