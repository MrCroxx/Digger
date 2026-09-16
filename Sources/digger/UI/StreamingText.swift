import Foundation

/// A small, bounded catch-up buffer. Network chunks never dictate the visual cadence.
/// Character boundaries keep emoji, combining marks and CJK intact.
struct StreamingText {
    private(set) var target = ""
    private(set) var visible = ""
    private var characters: [Character] = []
    private var offset = 0
    var isCaughtUp: Bool { offset == characters.count }

    mutating func receive(_ text: String) {
        guard text != target else { return }
        if text.hasPrefix(target) {
            characters.append(contentsOf: text.dropFirst(target.count))
        } else {
            let next = Array(text)
            let shared = zip(characters, next).prefix(while: { $0 == $1 }).count
            // A combining mark / emoji modifier can extend the last received
            // grapheme. Keep the preceding visible text instead of replaying it.
            offset = min(offset, shared)
            characters = next
            visible = String(next.prefix(offset))
        }
        target = text
    }

    mutating func advance(seconds: Double = 1.0 / 30.0) -> String {
        let remaining = characters.count - offset
        guard remaining > 0 else { return visible }
        // Drain bursts quickly, while spreading ordinary tokens over several frames.
        // A stalled network still reveals everything already received.
        let count = min(remaining, max(1, Int(ceil(max(80, Double(remaining) / 0.12) * min(seconds, 0.1)))))
        visible.append(contentsOf: characters[offset..<(offset + count)])
        offset += count
        return visible
    }
}

/// Display-only completion of the active inline tail. Never used for copying,
/// caching, stopped results or final results. cmark still owns all GFM parsing.
enum StreamingMarkdown {
    static func displaySource(_ source: String) -> String {
        var lines = source.components(separatedBy: "\n")
        var fence: (Character, Int)?
        var lastInlineStart = 0
        for (index, line) in lines.enumerated() {
            // Recognize fences inside quotes and list items as well as top-level code.
            let stripped = line.replacingOccurrences(of: #"^\s*(?:>\s*)*(?:[-+*]\s+|\d+[.)]\s+)?"#,
                                                     with: "", options: .regularExpression)
            let marker = stripped.first
            let run = marker.map { c in stripped.prefix(while: { $0 == c }).count } ?? 0
            if let open = fence {
                if marker == open.0, run >= open.1,
                   stripped.dropFirst(run).trimmingCharacters(in: .whitespaces).isEmpty { fence = nil }
                lastInlineStart = index + 1
            } else if (marker == "`" || marker == "~"), run >= 3 {
                fence = (marker!, run)
                lastInlineStart = index + 1
            } else if (line.trimmingCharacters(in: .whitespaces).isEmpty && index < lines.count - 1) ||
                        line.hasPrefix("    ") || line.hasPrefix("\t") {
                lastInlineStart = index + 1
            }
        }
        guard fence == nil, lastInlineStart < lines.count else { return source }
        // A GFM header is indistinguishable from a pipe paragraph until its
        // delimiter arrives. Hold only that ambiguous tail to avoid flashing raw
        // pipes and then replacing a paragraph with a much taller table.
        let candidate = lines[lastInlineStart].trimmingCharacters(in: .whitespaces)
        if candidate.hasPrefix("|"), lastInlineStart + 2 >= lines.count {
            let delimiter = lines.last!.trimmingCharacters(in: .whitespaces)
            let cells = delimiter.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            let complete = cells.count >= candidate.split(separator: "|").count && !cells.isEmpty &&
                cells.allSatisfy { $0.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil }
            if lastInlineStart == lines.count - 1 ||
                (!complete && delimiter.allSatisfy { "|-: \t".contains($0) }) {
                return lines[..<lastInlineStart].joined(separator: "\n")
            }
        }
        let tail = lines[lastInlineStart...].joined(separator: "\n")
        lines.replaceSubrange(lastInlineStart..., with: [completeInline(tail)])
        return lines.joined(separator: "\n")
    }

    private static func completeInline(_ source: String) -> String {
        var chars = Array(source)
        var markers: [String] = []
        var codeRun = 0
        var bracket: Int?
        var index = 0
        while index < chars.count {
            let char = chars[index]
            if char == "\\", codeRun == 0 { index += 2; continue }
            if char == "`" {
                var end = index
                while end < chars.count, chars[end] == "`" { end += 1 }
                let count = end - index
                if codeRun == count { codeRun = 0 }
                else if codeRun == 0 { codeRun = count }
                index = end
                continue
            }
            if codeRun > 0 { index += 1; continue }
            if char == "[" { bracket = index }
            if char == "]", let opening = bracket {
                if index + 1 < chars.count, chars[index + 1] == "(" {
                    var end = index + 2, depth = 1
                    while end < chars.count, depth > 0 {
                        if chars[end] == "\\" { end += 2; continue }
                        if chars[end] == "(" { depth += 1 }
                        if chars[end] == ")" { depth -= 1 }
                        end += 1
                    }
                    if depth > 0 {
                        let label = String(chars[(opening + 1)..<index])
                        return completeInline(String(chars[..<opening]) + label)
                    }
                    index = end
                    bracket = nil
                    continue
                }
                bracket = nil
            }
            if char == "*" || char == "_" || char == "~" {
                var end = index
                while end < chars.count, chars[end] == char { end += 1 }
                let run = end - index
                let before = index > 0 ? chars[index - 1] : nil
                let after = end < chars.count ? chars[end] : nil
                // Intraword underscores and single tildes are ordinary text.
                let intraword = char == "_" && before?.isLetter == true && after?.isLetter == true
                if !intraword, char != "~" || run == 2, run <= 3 {
                    let marker = String(repeating: String(char), count: run)
                    if markers.last == marker, before?.isWhitespace == false {
                        markers.removeLast()
                    } else if let after, !after.isWhitespace {
                        markers.append(marker)
                    } else if after == nil {
                        // A half closing delimiter should not flash as literal syntax.
                        chars.removeSubrange(index..<end)
                        break
                    }
                }
                index = end
                continue
            }
            index += 1
        }
        if let bracket {
            chars.remove(at: bracket)
            if bracket > 0, chars[bracket - 1] == "!" { chars.remove(at: bracket - 1) }
        }
        if codeRun > 0 {
            let delimiter = String(repeating: "`", count: codeRun)
            if String(chars).hasSuffix(delimiter) { chars.removeLast(codeRun) }
            else { chars.append(contentsOf: delimiter) }
        }
        // Close before trailing whitespace so CommonMark accepts the delimiter.
        let whitespace = chars.reversed().prefix(while: \.isWhitespace).count
        let suffix = String(chars.suffix(whitespace))
        chars.removeLast(whitespace)
        return String(chars) + markers.reversed().joined() + suffix
    }
}
