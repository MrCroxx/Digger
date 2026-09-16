import CryptoKit
import Foundation

actor TranslationDiskCache {
    struct RequestKey: Sendable {
        let inputHash: String
        let promptHash: String
        let systemPromptHash: String
        let modelHash: String
        let endpointHash: String
        let thinkEffortHash: String
        let keyHash: String
    }

    private struct CacheEntry: Codable {
        let version: Int
        let inputHash: String
        let promptHash: String
        let systemPromptHash: String
        let modelHash: String
        let endpointHash: String
        let thinkEffortHash: String
        let keyHash: String
        let output: String
        let createdAt: Date
    }

    private struct CacheFileInfo {
        let url: URL
        let size: Int64
        let modifiedAt: Date
    }

    static let shared = TranslationDiskCache()

    private static let schemaVersion = 2
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let cacheDirectoryURL: URL

    init(directory: URL? = nil) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        self.decoder = decoder

        cacheDirectoryURL = directory ?? Self.defaultCacheDirectoryURL()
    }

    static func makeRequestKey(
        input: String,
        prompt: String,
        systemPrompt: String,
        model: String,
        endpoint: String,
        thinkEffort: String
    ) -> RequestKey {
        let inputHash = sha256Hex(input)
        let promptHash = sha256Hex(prompt)
        let systemPromptHash = sha256Hex(systemPrompt)
        let modelHash = sha256Hex(model)
        let endpointHash = sha256Hex(endpoint)
        let thinkEffortHash = sha256Hex(thinkEffort)
        let keyHash = sha256Hex(
            "v\(schemaVersion)|\(inputHash)|\(promptHash)|\(systemPromptHash)|\(modelHash)|\(endpointHash)|\(thinkEffortHash)"
        )
        return RequestKey(
            inputHash: inputHash,
            promptHash: promptHash,
            systemPromptHash: systemPromptHash,
            modelHash: modelHash,
            endpointHash: endpointHash,
            thinkEffortHash: thinkEffortHash,
            keyHash: keyHash
        )
    }

    func cachedOutput(for key: RequestKey) -> String? {
        ensureCacheDirectoryIfNeeded()
        let fileURL = cacheFileURL(for: key)
        guard let data = try? Data(contentsOf: fileURL),
              let entry = try? decoder.decode(CacheEntry.self, from: data)
        else {
            return nil
        }
        guard entry.version == Self.schemaVersion,
              entry.keyHash == key.keyHash,
              entry.inputHash == key.inputHash,
              entry.promptHash == key.promptHash,
              entry.systemPromptHash == key.systemPromptHash,
              entry.modelHash == key.modelHash,
              entry.endpointHash == key.endpointHash,
              entry.thinkEffortHash == key.thinkEffortHash
        else {
            try? fileManager.removeItem(at: fileURL)
            return nil
        }
        if isExpired(createdAt: entry.createdAt) {
            try? fileManager.removeItem(at: fileURL)
            return nil
        }
        try? fileManager.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: fileURL.path
        )
        return entry.output
    }

    func storeOutput(_ output: String, for key: RequestKey) {
        let maxBytes = AppPreferences.translationCacheMaxBytes()
        if maxBytes <= 0 {
            clearAll()
            return
        }
        if AppPreferences.translationCacheTTLSeconds() <= 0 {
            clearAll()
            return
        }

        ensureCacheDirectoryIfNeeded()
        let fileURL = cacheFileURL(for: key)
        let entry = CacheEntry(
            version: Self.schemaVersion,
            inputHash: key.inputHash,
            promptHash: key.promptHash,
            systemPromptHash: key.systemPromptHash,
            modelHash: key.modelHash,
            endpointHash: key.endpointHash,
            thinkEffortHash: key.thinkEffortHash,
            keyHash: key.keyHash,
            output: output,
            createdAt: Date()
        )

        guard let data = try? encoder.encode(entry) else {
            return
        }
        try? data.write(to: fileURL, options: .atomic)
        try? fileManager.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: fileURL.path
        )
        pruneIfNeeded(maxBytes: maxBytes)
    }

    func pruneIfNeeded(maxBytes: Int64? = nil) {
        let limit = maxBytes ?? AppPreferences.translationCacheMaxBytes()
        if limit <= 0 {
            clearAll()
            return
        }

        ensureCacheDirectoryIfNeeded()
        removeExpiredEntries()
        var fileInfos = listCacheFiles()
        var totalSize = fileInfos.reduce(Int64(0)) { $0 + $1.size }
        guard totalSize > limit else {
            return
        }

        fileInfos.sort { lhs, rhs in
            lhs.modifiedAt < rhs.modifiedAt
        }
        for file in fileInfos {
            if totalSize <= limit {
                break
            }
            try? fileManager.removeItem(at: file.url)
            totalSize -= file.size
        }
    }

    func cacheDirectoryLocation() -> URL {
        ensureCacheDirectoryIfNeeded()
        return cacheDirectoryURL
    }

    private func clearAll() {
        ensureCacheDirectoryIfNeeded()
        for file in listCacheFiles() {
            try? fileManager.removeItem(at: file.url)
        }
    }

    private func removeExpiredEntries() {
        for file in listCacheFiles() {
            guard let data = try? Data(contentsOf: file.url),
                  let entry = try? decoder.decode(CacheEntry.self, from: data) else {
                continue
            }
            if isExpired(createdAt: entry.createdAt) {
                try? fileManager.removeItem(at: file.url)
            }
        }
    }

    private func ensureCacheDirectoryIfNeeded() {
        try? fileManager.createDirectory(
            at: cacheDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    private func cacheFileURL(for key: RequestKey) -> URL {
        cacheDirectoryURL.appendingPathComponent("\(key.keyHash).json", isDirectory: false)
    }

    private func listCacheFiles() -> [CacheFileInfo] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: cacheDirectoryURL,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .contentModificationDateKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [CacheFileInfo] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .contentModificationDateKey
            ]),
            values.isRegularFile == true
            else {
                continue
            }
            files.append(
                CacheFileInfo(
                    url: url,
                    size: Int64(values.fileSize ?? 0),
                    modifiedAt: values.contentModificationDate ?? .distantPast
                )
            )
        }
        return files
    }

    private static func defaultCacheDirectoryURL() -> URL {
        if let cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            return cacheRoot
                .appendingPathComponent("digger", isDirectory: true)
                .appendingPathComponent("translation-cache", isDirectory: true)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("digger", isDirectory: true)
            .appendingPathComponent("translation-cache", isDirectory: true)
    }

    private static func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func isExpired(createdAt: Date) -> Bool {
        let ttl = AppPreferences.translationCacheTTLSeconds()
        guard ttl > 0 else {
            return true
        }
        return Date().timeIntervalSince(createdAt) > ttl
    }
}
