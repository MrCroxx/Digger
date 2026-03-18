import CoreServices
import Foundation

struct DictionaryLookupResult {
    let plainText: String
    let markdownText: String
}

enum SystemDictionaryService {
    static func lookup(text: String) -> DictionaryLookupResult? {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return nil
        }
        let range = CFRange(location: 0, length: query.utf16.count)
        guard let value = DCSCopyTextDefinition(nil, query as CFString, range)?.takeRetainedValue() else {
            logLookupFailure(query: query)
            return nil
        }
        let definition = value as String
        let plainText = normalizeDefinitionText(definition)
        guard !plainText.isEmpty else {
            logLookupResult(
                query: query,
                rawDefinition: definition,
                normalizedText: plainText,
                markdownText: ""
            )
            return nil
        }
        let markdownText = buildMarkdown(from: plainText)
        logLookupResult(
            query: query,
            rawDefinition: definition,
            normalizedText: plainText,
            markdownText: markdownText
        )
        return DictionaryLookupResult(
            plainText: plainText,
            markdownText: markdownText
        )
    }

    private static func normalizeDefinitionText(_ raw: String) -> String {
        let rawNormalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        let looksLikeHTML = rawNormalized.contains("<") && rawNormalized.contains(">")
        var normalized = rawNormalized
        if looksLikeHTML {
            normalized = htmlToText(rawNormalized)
        }
        normalized = normalized.replacingOccurrences(
            of: #"\s+\|\s+"#,
            with: "\n\n",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: #"\s+([•▪◦])\s+"#,
            with: "\n\n$1 ",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: #"\s+(\d+\.)\s+"#,
            with: "\n\n$1 ",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: #";\s+"#,
            with: ";\n\n",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: #"(?i)\s+(noun|verb|adjective|adverb|pronoun|preposition|conjunction|interjection|determiner|article|abbreviation)\s+"#,
            with: "\n\n$1\n\n",
            options: .regularExpression
        )
        normalized = normalized.components(separatedBy: CharacterSet.newlines).joined(separator: "\n")

        if !normalized.contains("\n"), normalized.contains("\\n") {
            normalized = normalized.replacingOccurrences(of: "\\n", with: "\n")
        }

        if !normalized.contains("\n") {
            normalized = injectFallbackLineBreaks(normalized)
        }

        normalized = normalized.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func htmlToText(_ html: String) -> String {
        var preprocessed = html
        preprocessed = preprocessed.replacingOccurrences(
            of: #"(?i)<br\s*/?>"#,
            with: "\n",
            options: .regularExpression
        )
        preprocessed = preprocessed.replacingOccurrences(
            of: #"(?i)</(p|div|li|ul|ol|h1|h2|h3|h4|h5|h6|tr|table)>"#,
            with: "\n",
            options: .regularExpression
        )
        preprocessed = preprocessed.replacingOccurrences(
            of: #"(?i)<li[^>]*>"#,
            with: "\n• ",
            options: .regularExpression
        )

        guard let data = preprocessed.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return preprocessed
        }
        return attributed.string.replacingOccurrences(of: "\r\n", with: "\n")
    }

    private static func injectFallbackLineBreaks(_ text: String) -> String {
        var value = text
        value = value.replacingOccurrences(
            of: #"\s+\|\s+"#,
            with: "\n\n",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"\s+(\d+\.)\s+"#,
            with: "\n$1 ",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"\s*([•▪◦])\s*"#,
            with: "\n$1 ",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #";\s+"#,
            with: ";\n\n",
            options: .regularExpression
        )
        return value
    }

    private static func buildMarkdown(from plainText: String) -> String {
        var normalized = plainText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        normalized = normalized.replacingOccurrences(
            of: #"\s*\|\s*"#,
            with: "\n\n",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: #"\s*([•▪◦·])\s*"#,
            with: "\n• ",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: #"\s+(\d+\.)\s+"#,
            with: "\n$1 ",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: #"(?i)\s+(noun|verb|adjective|adverb|pronoun|preposition|conjunction|interjection|determiner|article|abbreviation)\s+"#,
            with: "\n\n$1\n\n",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: #";\s+(?=[A-Za-z0-9])"#,
            with: ";\n",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )

        let rawLines = normalized.components(separatedBy: "\n")
        var segments: [[String]] = []
        var currentSegment: [String] = []
        for line in rawLines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if !currentSegment.isEmpty {
                    segments.append(currentSegment)
                    currentSegment = []
                }
                continue
            }
            currentSegment.append(trimmed)
        }
        if !currentSegment.isEmpty {
            segments.append(currentSegment)
        }
        guard !segments.isEmpty else {
            return plainText
        }

        var output: [String] = []
        for segmentIndex in segments.indices {
            let segment = segments[segmentIndex]
            var inList = false
            for lineIndex in segment.indices {
                let line = segment[lineIndex]

                if isPartOfSpeech(line) {
                    if !output.isEmpty, output.last != "" {
                        output.append("")
                    }
                    output.append("_\(line.lowercased())_")
                    output.append("")
                    inList = false
                    continue
                }

                if let item = bulletItem(from: line) {
                    if !inList {
                        if !output.isEmpty, output.last != "" {
                            output.append("")
                        }
                        inList = true
                    }
                    output.append("- \(item)")
                    continue
                }

                if inList {
                    output.append("")
                    inList = false
                }

                if lineIndex == 0, isLikelyEntryHeading(line), !line.hasPrefix("- "), !line.hasPrefix("1.") {
                    output.append("**\(line)**")
                } else {
                    output.append(line)
                }
            }

            if segmentIndex < segments.count - 1 {
                if !output.isEmpty, output.last != "" {
                    output.append("")
                }
                output.append("")
            }
        }

        let markdown = output.joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return markdown.isEmpty ? plainText : markdown
    }

    private static func bulletItem(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("• ") || trimmed.hasPrefix("▪ ") || trimmed.hasPrefix("◦ ") || trimmed.hasPrefix("· ") {
            return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if trimmed.hasPrefix("- ") {
            return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil {
            return trimmed
        }
        return nil
    }

    private static func isLikelyEntryHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 120 || trimmed.hasSuffix(".") {
            return false
        }
        if trimmed.contains("·") || trimmed.contains("/") {
            return true
        }
        let wordCount = trimmed.split(whereSeparator: { $0.isWhitespace }).count
        if wordCount <= 6 {
            let lower = trimmed.lowercased()
            if lower.range(of: #"^[a-z][a-z\-’']*$"#, options: .regularExpression) != nil {
                return true
            }
            if lower.range(of: #"^[a-z][a-z\-’']+\s+[a-z].*$"#, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }

    private static func isPartOfSpeech(_ line: String) -> Bool {
        let value = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return [
            "noun",
            "verb",
            "adjective",
            "adverb",
            "pronoun",
            "preposition",
            "conjunction",
            "interjection",
            "determiner",
            "article",
            "abbreviation"
        ].contains(value)
    }

    private static func logLookupFailure(query: String) {
        print("[DictionaryDebug] query=\(query)")
        print("[DictionaryDebug] result=nil")
    }

    private static func logLookupResult(
        query: String,
        rawDefinition: String,
        normalizedText: String,
        markdownText: String
    ) {
        print("[DictionaryDebug] query=\(query)")
        print("[DictionaryDebug] raw_length=\(rawDefinition.count) normalized_length=\(normalizedText.count) markdown_length=\(markdownText.count)")
        logTokenPositions(in: rawDefinition)
        logStringArray("raw_by_newline", rawDefinition.components(separatedBy: CharacterSet.newlines))
        logStringArray("raw_by_pipe", rawDefinition.components(separatedBy: "|"))
        logStringArray(
            "normalized_paragraphs",
            normalizedText.components(separatedBy: "\n\n")
        )
        logStringArray(
            "normalized_lines",
            normalizedText.components(separatedBy: "\n")
        )
        logStringArray(
            "markdown_blocks",
            markdownText.components(separatedBy: "\n\n")
        )
        logStringArray(
            "markdown_lines",
            markdownText.components(separatedBy: "\n")
        )
    }

    private static func logStringArray(_ label: String, _ values: [String]) {
        let trimmedValues = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        print("[DictionaryDebug] \(label)_count=\(trimmedValues.count)")
        for (index, value) in trimmedValues.enumerated() {
            print("[DictionaryDebug] \(label)[\(index)]=\(escaped(value))")
        }
    }

    private static func logTokenPositions(in text: String) {
        var tokens: [String] = []
        for (offset, scalar) in text.unicodeScalars.enumerated() {
            switch scalar.value {
            case 10:
                tokens.append("LF@\(offset)")
            case 13:
                tokens.append("CR@\(offset)")
            case 0x2028:
                tokens.append("LS@\(offset)")
            case 0x2029:
                tokens.append("PS@\(offset)")
            case 124:
                tokens.append("PIPE@\(offset)")
            case 59:
                tokens.append("SEMI@\(offset)")
            case 8226:
                tokens.append("BULLET@\(offset)")
            default:
                continue
            }
        }
        print("[DictionaryDebug] separators=\(tokens.joined(separator: ","))")
    }

    private static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
