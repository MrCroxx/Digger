#if DEBUG
import AppKit

/// Authored examples for documentation, rendered by the actual popup and settings views.
/// Uses PreviewMode's isolated preferences; no provider requests or real credentials.
@MainActor
enum PreviewShowcase {
    private static var english: Bool { AppPreferences.language() == .english }

    static func configure() {
        AppPreferences.setPopupMaxWidth(700)
        AppPreferences.setPopupMaxHeight(760)
        AppPreferences.setPopupOriginalCollapsed(false)
        AppPreferences.setCustomFunctions([
            CustomFunction(title: english ? "Translation" : "翻译",
                           prompt: english ? "Translate into natural English. Preserve the original formatting."
                               : "翻译成自然流畅的中文，保留原文格式。"),
            CustomFunction(title: english ? "Key points" : "要点",
                           prompt: english ? "Summarize the key ideas in two concise bullet points."
                               : "用两条简洁的要点概括核心内容。"),
            CustomFunction(title: english ? "Explain" : "解释",
                           prompt: english ? "Explain the idea with a short example and a practical comparison."
                               : "用一个简短示例和实际对比解释这个概念。", isEnabled: false)
        ])
    }

    static func show(near anchor: CGPoint, code: Bool) {
        let id = UUID()
        let titles = code ? [english ? "Explain" : "解释"]
            : [english ? "Translation" : "翻译", english ? "Key points" : "要点"]
        let functions = titles.map { PopupFunction(id: UUID(), title: $0, prompt: "", isTranslation: false) }
        let original = code
            ? (english ? "When should I use a cache, and when should I fetch fresh data?"
                : "什么时候应该使用缓存，什么时候应该重新获取数据？")
            : (english ? "缓存让重复读取更快，但它不应该替你决定什么才是最新信息。优先展示已有结果，并在需要时重新获取，让速度与准确性各得其所。"
                : "A cache makes repeated reads faster, but it should not decide what counts as up to date. Show the saved result first, then fetch fresh data when needed: speed and accuracy each have their place.")
        selectionPopup.showLoading(original: original, near: anchor, requestID: id, functions: functions)
        let results = code ? [codeResult] : [
            english
                ? "A cache makes repeated reads faster, but it should not decide what counts as **up to date**. Show the saved result first, then fetch fresh data when needed: speed and accuracy each have their place."
                : "缓存让重复读取更快，但它不应该替你决定什么才是**最新信息**。优先展示已有结果，并在需要时重新获取，让速度与准确性各得其所。",
            english
                ? "- Reuse saved results for a faster first read.\n- Refresh when freshness matters."
                : "- 复用已有结果，让首次阅读更快。\n- 需要最新信息时，主动重新获取。"
        ]
        for (function, result) in zip(functions, results) {
            selectionPopup.updateResult(result, for: id, functionID: function.id, near: anchor,
                                        isFinal: true, isCacheHit: false)
        }
    }

    private static var codeResult: String {
        english ? """
        ### Fast to read. Easy to refresh.

        A cache keeps a previous result close at hand. Use it when the same request is likely to return the same answer.

        | Read from cache | Fetch fresh data |
        | :--- | :--- |
        | Saved translations | Live status |
        | Existing notes | Manual refresh |

        ```swift
        let result = cache.value(for: selection) ?? provider.translate(selection, preserving: [.headings, .lists, .codeBlocks])
        ```

        > Give the reader a quick answer and a clear way to refresh it.
        """ : """
        ### 读取更快，更新更从容。

        缓存把已有结果保留在手边。同一个请求很可能返回同一个答案时，就可以复用它。

        | 读取缓存 | 重新获取 |
        | :--- | :--- |
        | 重新打开一段翻译 | 检查实时状态 |
        | 回顾已保存的笔记 | 主动重试一次请求 |

        ```swift
        let result = cache.value(for: selection) ?? provider.translate(selection, preserving: [.headings, .lists, .codeBlocks])
        ```

        > 让读者快速得到答案，也能随时主动更新。
        """
    }
}
#endif
