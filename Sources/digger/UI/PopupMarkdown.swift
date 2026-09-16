import Foundation
import MarkdownUI
import cmark_gfm
import cmark_gfm_extensions

/// MarkdownUI 2.4.1 turns every sibling into a checkbox when a list contains any
/// task item. Separate runs of ordinary/task items for display only, using cmark's
/// actual tree so code fences, indentation, and quoted/nested lists remain intact.
/// Raw source in ResultModel is never rewritten and remains the copy/cache value.
enum PopupMarkdown {
    private typealias Node = UnsafeMutablePointer<cmark_node>

    struct Block: Identifiable, Equatable {
        let id: Int
        let source: String
        let content: MarkdownUI.MarkdownContent
        // A useful diagnostic: an unchanged block keeps its parsed value.
        let revision = UUID()
    }

    /// Parse the document for correct GFM/reference-link semantics, but only build
    /// MarkdownUI values for changed blocks. Stable slots keep preceding paragraphs
    /// and their measured margins out of the active tail's SwiftUI identity changes.
    static func blocks(_ source: String, reusing previous: [Block] = []) -> [Block] {
        cmark_gfm_core_extensions_ensure_registered()
        guard let parser = cmark_parser_new(CMARK_OPT_DEFAULT) else { return [] }
        defer { cmark_parser_free(parser) }
        for name in ["autolink", "strikethrough", "tagfilter", "tasklist", "table"] {
            if let ext = cmark_find_syntax_extension(name) { cmark_parser_attach_syntax_extension(parser, ext) }
        }
        cmark_parser_feed(parser, source, source.utf8.count)
        guard let document = cmark_parser_finish(parser) else { return [] }
        defer { cmark_node_free(document) }
        _ = restoreTaskMarkers(in: document, lines: source.components(separatedBy: "\n"))
        _ = separateMixedLists(in: document)
        return children(of: document).enumerated().map { index, node in
            // Rendered HTML includes resolved reference destinations and task state.
            let rendered = cmark_render_html(node, CMARK_OPT_DEFAULT, cmark_parser_get_syntax_extensions(parser))
            let key = rendered.map { String(cString: $0) } ?? ""
            if let rendered { free(rendered) }
            if previous.indices.contains(index), previous[index].source == key { return previous[index] }
            return Block(id: index, source: key, content: block(node))
        }
    }
    static func parse(_ source: String) -> MarkdownUI.MarkdownContent {
        guard ["[ ]", "[x]", "[X]"].contains(where: source.contains) else { return .init(source) }
        cmark_gfm_core_extensions_ensure_registered()
        guard let parser = cmark_parser_new(CMARK_OPT_DEFAULT) else { return .init(source) }
        defer { cmark_parser_free(parser) }
        for name in ["autolink", "strikethrough", "tagfilter", "tasklist", "table"] {
            if let ext = cmark_find_syntax_extension(name) { cmark_parser_attach_syntax_extension(parser, ext) }
        }
        cmark_parser_feed(parser, source, source.utf8.count)
        guard let document = cmark_parser_finish(parser) else { return .init(source) }
        defer { cmark_node_free(document) }
        let repairedTasks = restoreTaskMarkers(in: document, lines: source.components(separatedBy: "\n"))
        let splitLists = separateMixedLists(in: document)
        guard repairedTasks || splitLists else { return .init(source) }
        return content(of: document)
    }

    private static func content(of node: Node) -> MarkdownUI.MarkdownContent {
        MarkdownUI.MarkdownContent {
            for child in children(of: node) { block(child) }
        }
    }

    private static func block(_ node: Node) -> MarkdownUI.MarkdownContent {
        if cmark_node_get_type(node) == CMARK_NODE_BLOCK_QUOTE {
            return MarkdownUI.Blockquote { content(of: node) }._markdownContent
        }
        if cmark_node_get_type(node) == CMARK_NODE_LIST {
            let items = children(of: node)
            let tight = cmark_node_get_list_tight(node) != 0
            if let first = items.first, isTask(first) {
                return MarkdownUI.TaskList(of: items, tight: tight) { item in
                    MarkdownUI.TaskListItem(isCompleted: cmark_gfm_extensions_get_tasklist_item_checked(item)) {
                        content(of: item)
                    }
                }._markdownContent
            }
            if cmark_node_get_list_type(node) == CMARK_ORDERED_LIST {
                return MarkdownUI.NumberedList(of: items, tight: tight, start: Int(cmark_node_get_list_start(node))) { item in
                    MarkdownUI.ListItem { content(of: item) }
                }._markdownContent
            }
            return MarkdownUI.BulletedList(of: items, tight: tight) { item in
                MarkdownUI.ListItem { content(of: item) }
            }._markdownContent
        }
        guard let rendered = cmark_render_commonmark(node, CMARK_OPT_DEFAULT, 0) else { return .init("") }
        defer { free(rendered) }
        return .init(String(cString: rendered))
    }

    private static func children(of node: Node) -> [Node] {
        var result: [Node] = []
        var next = cmark_node_first_child(node)
        while let child = next {
            result.append(child)
            next = cmark_node_next(child)
        }
        return result
    }

    private static func isTask(_ item: Node) -> Bool {
        String(cString: cmark_node_get_type_string(item)) == "tasklist"
    }

    // cmark can leave a task marker as plain text inside quoted nested lists.
    // Check its source position too, so an escaped \[x] stays literal.
    private static func restoreTaskMarkers(in parent: Node, lines: [String]) -> Bool {
        var changed = false
        for item in children(of: parent) {
            if restoreTaskMarkers(in: item, lines: lines) { changed = true }
            guard cmark_node_get_type(item) == CMARK_NODE_ITEM, !isTask(item),
                  let paragraph = cmark_node_first_child(item), cmark_node_get_type(paragraph) == CMARK_NODE_PARAGRAPH,
                  let text = cmark_node_first_child(paragraph), cmark_node_get_type(text) == CMARK_NODE_TEXT,
                  let value = cmark_node_get_literal(text) else { continue }
            let literal = String(cString: value)
            guard ["[ ] ", "[x] ", "[X] "].contains(where: literal.hasPrefix) else { continue }
            let line = Int(cmark_node_get_start_line(text)) - 1
            let column = Int(cmark_node_get_start_column(text)) - 1
            guard lines.indices.contains(line), column >= 0,
                  String(decoding: lines[line].utf8.dropFirst(column).prefix(4), as: UTF8.self) == String(literal.prefix(4)),
                  let ext = cmark_find_syntax_extension("tasklist"),
                  let task = cmark_node_new_with_ext(CMARK_NODE_ITEM, ext) else { continue }
            cmark_gfm_extensions_set_tasklist_item_checked(task, !literal.hasPrefix("[ ]"))
            cmark_node_set_literal(text, String(literal.dropFirst(4)))
            cmark_node_insert_before(item, task)
            for child in children(of: item) {
                cmark_node_unlink(child)
                cmark_node_append_child(task, child)
            }
            cmark_node_unlink(item)
            cmark_node_free(item)
            changed = true
        }
        return changed
    }

    private static func separateMixedLists(in parent: Node) -> Bool {
        var changed = false
        for node in children(of: parent) {
            if separateMixedLists(in: node) { changed = true }
            guard cmark_node_get_type(node) == CMARK_NODE_LIST else { continue }
            let items = children(of: node)
            guard let first = items.first, items.contains(where: { isTask($0) != isTask(first) }) else { continue }
            let kind = cmark_node_get_list_type(node)
            let start = cmark_node_get_list_start(node)
            let tight = cmark_node_get_list_tight(node)
            let delimiter = cmark_node_get_list_delim(node)
            var previous = node
            var group: Node?
            var taskKind = isTask(first)
            for (index, item) in items.enumerated() {
                if group == nil || isTask(item) != taskKind {
                    guard let list = cmark_node_new(CMARK_NODE_LIST) else { continue }
                    cmark_node_set_list_type(list, kind)
                    cmark_node_set_list_start(list, start + Int32(index))
                    cmark_node_set_list_tight(list, tight)
                    cmark_node_set_list_delim(list, delimiter)
                    cmark_node_insert_after(previous, list)
                    previous = list
                    group = list
                    taskKind = isTask(item)
                }
                if let group {
                    cmark_node_unlink(item)
                    cmark_node_append_child(group, item)
                }
            }
            cmark_node_unlink(node)
            cmark_node_free(node)
            changed = true
        }
        return changed
    }
}
