import Foundation
import SwiftSoup

/// Converts the copied selection, not the whole page, without a web view or network I/O.
/// Clipboard fragment markers retain their structural ancestors (e.g. an outer <ul>).
enum HTMLSelectionMarkdown {
    static func convert(_ html: String) -> String? {
        guard let document = try? SwiftSoup.parse(html), let body = document.body() else { return nil }
        if html.range(of: "<!--StartFragment-->", options: .caseInsensitive) != nil,
           html.range(of: "<!--EndFragment-->", options: .caseInsensitive) != nil {
            var selected = false
            _ = retainSelection(in: document, selected: &selected)
        }
        let result = render(body).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private static func retainSelection(in node: Node, selected: inout Bool) -> Bool {
        if let comment = node as? Comment {
            let marker = comment.getData().trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if marker == "startfragment" { selected = true }
            if marker == "endfragment" { selected = false }
            return false
        }
        if node is TextNode { return selected }
        let keepEmpty = selected
        if let list = node as? Element, list.tagNameNormal() == "ol" {
            var number = Int(attribute(list, "start")) ?? 1
            for item in list.getChildNodes().compactMap({ $0 as? Element }) where item.tagNameNormal() == "li" {
                number = Int(attribute(item, "value")) ?? number
                _ = try? item.attr("value", String(number))
                number += 1
            }
        }
        for child in node.getChildNodes() {
            if !retainSelection(in: child, selected: &selected) { try? child.remove() }
        }
        return !node.getChildNodes().isEmpty || keepEmpty
    }

    private static func renderChildren(_ node: Node) -> String {
        node.getChildNodes().map(render).joined()
    }

    private static func render(_ node: Node) -> String {
        if let text = node as? TextNode { return escape(collapse(text.getWholeText())) }
        guard let element = node as? Element else { return "" }
        let tag = element.tagNameNormal()
        if ["script", "style", "head", "noscript", "template", "svg"].contains(tag) || element.hasAttr("hidden") { return "" }
        switch tag {
        case "ul", "ol": return "\n" + list(element) + "\n"
        case "pre":
            let text = verbatim(element)
            let fence = String(repeating: "`", count: max(3, longestBacktickRun(text) + 1))
            let code = element.getChildNodes().compactMap { $0 as? Element }.first { $0.tagNameNormal() == "code" }
            let language = attribute(code, "class").split(separator: " ").first { $0.hasPrefix("language-") }
                .map { String($0.dropFirst(9)).filter { $0.isLetter || $0.isNumber || $0 == "-" } } ?? ""
            return "\n\n" + fence + language + "\n" + text + (text.hasSuffix("\n") ? "" : "\n") + fence + "\n\n"
        case "code", "kbd", "samp":
            let text = verbatim(element).replacingOccurrences(of: "\n", with: " ")
            let fence = String(repeating: "`", count: max(1, longestBacktickRun(text) + 1))
            let padding = text.hasPrefix("`") || text.hasSuffix("`") || text.hasPrefix(" ") || text.hasSuffix(" ") ? " " : ""
            return fence + padding + text + padding + fence
        case "a":
            let label = renderChildren(element)
            guard let href = destination(attribute(element, "href")), !label.isEmpty else { return label }
            return "[" + label + "](<" + href + ">)"
        case "img":
            let alt = escape(attribute(element, "alt"))
            guard let src = destination(attribute(element, "src")) else { return alt }
            return "![" + alt + "](<" + src + ">)"
        case "strong", "b": return wrap(renderChildren(element), with: "**")
        case "em", "i": return wrap(renderChildren(element), with: "*")
        case "del", "s", "strike": return wrap(renderChildren(element), with: "~~")
        case "br": return "  \n"
        case "hr": return "\n\n---\n\n"
        case "blockquote":
            return "\n\n" + renderChildren(element).trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n") + "\n\n"
        case "table": return table(element)
        case "h1", "h2", "h3", "h4", "h5", "h6":
            return "\n\n" + String(repeating: "#", count: Int(tag.suffix(1)) ?? 1) + " "
                + renderChildren(element).trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n"
        case "p", "div", "section", "article", "header", "footer", "dl", "dt", "dd":
            let content = renderChildren(element).trimmingCharacters(in: .whitespacesAndNewlines)
            return content.isEmpty ? "" : "\n\n" + content + "\n\n"
        default: return renderChildren(element)
        }
    }

    private static func list(_ element: Element) -> String {
        var number = Int(attribute(element, "start")) ?? 1
        let ordered = element.tagNameNormal() == "ol"
        return element.getChildNodes().compactMap { $0 as? Element }.filter { $0.tagNameNormal() == "li" }.map { item in
            if let value = Int(attribute(item, "value")) { number = value }
            let marker = ordered ? "\(number). " : "- "
            number += 1
            let content = renderChildren(item).trimmingCharacters(in: .whitespacesAndNewlines)
            let lines = content.components(separatedBy: "\n")
            let indentation = String(repeating: " ", count: marker.count)
            return marker + (lines.first ?? "") + lines.dropFirst().map { "\n" + ($0.isEmpty ? "" : indentation + $0) }.joined()
        }.joined(separator: "\n")
    }

    private static func table(_ element: Element) -> String {
        let rows = (try? element.select("tr").array()) ?? []
        let cells = rows.map { row in
            row.getChildNodes().compactMap { $0 as? Element }.filter { ["td", "th"].contains($0.tagNameNormal()) }.map {
                renderChildren($0).trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\n", with: " ")
            }
        }.filter { !$0.isEmpty }
        guard let first = cells.first else { return "" }
        let width = cells.map(\.count).max() ?? first.count
        func row(_ values: [String]) -> String {
            "| " + (values + Array(repeating: "", count: max(0, width - values.count))).joined(separator: " | ") + " |"
        }
        return "\n\n" + ([row(first), row(Array(repeating: "---", count: width))] + cells.dropFirst().map(row)).joined(separator: "\n") + "\n\n"
    }

    private static func attribute(_ element: Element?, _ name: String) -> String { (try? element?.attr(name)) ?? "" }
    private static func verbatim(_ node: Node) -> String {
        if let text = node as? TextNode { return text.getWholeText() }
        return node.getChildNodes().map(verbatim).joined()
    }
    private static func collapse(_ value: String) -> String {
        value.replacingOccurrences(of: "[\\s\\u00a0]+", with: " ", options: .regularExpression)
    }
    private static func escape(_ value: String) -> String {
        let special = Set("\\`*_{}[]<>()#+-.!|>~")
        return value.map { special.contains($0) ? "\\" + String($0) : String($0) }.joined()
    }
    private static func wrap(_ value: String, with marker: String) -> String {
        let core = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !core.isEmpty else { return value }
        return (value.first?.isWhitespace == true ? " " : "") + marker + core + marker + (value.last?.isWhitespace == true ? " " : "")
    }
    private static func longestBacktickRun(_ value: String) -> Int {
        var longest = 0, current = 0
        for character in value {
            current = character == "`" ? current + 1 : 0
            longest = max(longest, current)
        }
        return longest
    }
    private static func destination(_ value: String) -> String? {
        guard !value.isEmpty else { return nil }
        if let scheme = URLComponents(string: value)?.scheme, !["http", "https", "mailto"].contains(scheme.lowercased()) { return nil }
        return value.replacingOccurrences(of: "<", with: "%3C").replacingOccurrences(of: ">", with: "%3E")
            .replacingOccurrences(of: "\n", with: "%0A").replacingOccurrences(of: "\r", with: "%0D")
    }
}
