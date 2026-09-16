#if DEBUG
import AppKit
import SwiftUI

/// Offline, isolated fixture for reviewing real native windows without API calls or permissions.
@MainActor
enum PreviewMode {
    static let markdownFixture = """
    ## 保留格式，边生成边阅读

    **粗体**、*斜体*、~~删除线~~和[链接](https://example.com)。

    - 精简的阅读浮窗
      - 保留嵌套层级
    - [x] 支持流式输出

    | 功能 | 状态 |
    | :--- | ---: |
    | 翻译 | 就绪 |
    | 摘要 | 就绪 |

    > 原文与结果都可以复制为 Markdown。

    ```swift
    let text = "**literal**"
    print(text)
    ```
    """

    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        AppPreferences.defaults.removePersistentDomain(forName: "com.mrcroxx.digger.preview.preferences")
        let args = ProcessInfo.processInfo.arguments
        AppPreferences.setLanguage(args.contains("--english") ? .english : (args.contains("--japanese") ? .japanese : .chineseSimplified))
        if args.contains("--dark") { app.appearance = NSAppearance(named: .darkAqua) }
        if args.contains("--small") {
            AppPreferences.setPopupMaxWidth(360)
            AppPreferences.setPopupMaxHeight(280)
        }
        if args.contains("--expanded") { AppPreferences.setPopupOriginalCollapsed(false) }
        let menu = MainMenuController()
        app.mainMenu = menu.buildMainMenu()
        let preferences = PreferencesWindowController(
            onPopupFontSizeChange: { selectionPopup.applyPopupTextSize($0) },
            onPopupOpacityChange: { selectionPopup.applyPopupOpacity($0) },
            onPopupLayoutChange: { selectionPopup.refreshLayout() },
            onLanguageChange: { selectionPopup.applyStrings(); menu.applyStrings() },
            onCustomFunctionsChange: {})
        let welcome = WelcomeWindowController()
        welcome.onOpenPreferences = { preferences.show() }
        let menuBar = MenuBarController(preferencesController: preferences, welcomeController: welcome)
        selectionPopup.onOpenPreferences = { preferences.show() }
        let showFixture = {
            let id = UUID()
            let functions = [PopupFunction(id: UUID(), title: "翻译", prompt: "", isTranslation: true),
                             PopupFunction(id: UUID(), title: "摘要", prompt: "", isTranslation: false)]
            let frame = NSScreen.main?.visibleFrame ?? .zero
            let anchor = CGPoint(x: frame.midX - AppPreferences.popupMaxWidth() / 2 - 14, y: frame.midY + AppPreferences.popupMaxHeight() / 2 + 14)
            let htmlPathIndex = args.firstIndex(of: "--html")
            let htmlPath = htmlPathIndex.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
            let html = htmlPath.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }
            let htmlMarkdown = html.flatMap(HTMLSelectionMarkdown.convert)
            let fixture = htmlMarkdown ?? Self.markdownFixture
            let markdownPreview = htmlMarkdown != nil || args.contains("--markdown") || args.contains("--markdown-stream")
            selectionPopup.showLoading(original: markdownPreview ? fixture : "Good design is as little design as possible. Less, but better — because it concentrates on the essential aspects.",
                                       near: anchor, requestID: id, functions: markdownPreview ? Array(functions.prefix(1)) : functions)
            if markdownPreview {
                if htmlMarkdown != nil { selectionPopup.model.sections[0] = ResultModel.Section(id: functions[0].id, title: "HTML → Markdown") }
                if args.contains("--markdown-stream") {
                    Task { @MainActor in
                        let window = app.windows.first { $0.isVisible && $0.title == "Digger" }
                        let frame = window?.frame
                        let characters = Array(fixture)
                        for end in stride(from: 8, to: characters.count + 8, by: 8) {
                            try? await Task.sleep(for: .milliseconds(50))
                            guard selectionPopup.model.requestID == id else { return }
                            let count = min(end, characters.count)
                            selectionPopup.updateResult(String(characters.prefix(count)), for: id, functionID: functions[0].id,
                                near: anchor, isFinal: count == characters.count, isCacheHit: false)
                            assert(window?.frame == frame, "Streaming changed the popup frame")
                        }
                        print("[Digger preview] Markdown stream complete; window frame remained stable.")
                    }
                } else {
                    selectionPopup.updateResult(fixture, for: id, functionID: functions[0].id, near: anchor, isFinal: true, isCacheHit: false)
                }
                return
            }
            if args.contains("--loading") { return }
            if args.contains("--error") {
                selectionPopup.updateResult("无法连接到服务，请检查网络或在设置中确认 API 地址。", for: id, functionID: functions[0].id, near: anchor, isFinal: true, isCacheHit: false, isError: true)
                return
            }
            if args.contains("--long") {
                selectionPopup.applyPopupTextSize(20)
                let sample = "## 保留阅读空间\n\n正文可以选中和复制，长内容在窗口内滚动。\n\n```swift\nlet message = \"A long line of literal code stays readable inside a narrow window.\"\nprint(message)\n```\n\n"
                selectionPopup.updateResult(String(repeating: sample, count: 8), for: id, functionID: functions[0].id, near: anchor, isFinal: false, isCacheHit: false)
                return
            }
            selectionPopup.updateResult("好的设计，是尽可能少的设计。\n\n**更少，却更好。** 因为它专注于本质，而不是让产品背负不必要的负担。\n\n> 回归纯粹，回归简单。", for: id, functionID: functions[0].id, near: anchor, isFinal: true, isCacheHit: false)
            selectionPopup.updateResult("设计的价值在于去除多余，让真正重要的部分清晰可见。", for: id, functionID: functions[1].id, near: anchor, isFinal: true, isCacheHit: true)
        }
        selectionPopup.onRetry = { _, _ in showFixture() }
        if ProcessInfo.processInfo.arguments.contains("--welcome") { welcome.show() }
        else if ProcessInfo.processInfo.arguments.contains("--settings") { preferences.show() }
        else { showFixture() }
        if let index = args.firstIndex(of: "--render"), args.indices.contains(index + 1) {
            let path = args[index + 1]
            Task { @MainActor in
                let delayIndex = args.firstIndex(of: "--render-delay")
                let delay = delayIndex.flatMap { args.indices.contains($0 + 1) ? Double(args[$0 + 1]) : nil } ?? 1
                try? await Task.sleep(for: .seconds(min(max(delay, 0.1), 30)))
                if args.contains("--scrollbars") {
                    func revealScrollers(in view: NSView) {
                        if let scroll = view as? NSScrollView {
                            assert(scroll.scrollerStyle == .overlay)
                            scroll.flashScrollers()
                        }
                        for child in view.subviews { revealScrollers(in: child) }
                    }
                    if let view = app.windows.first(where: { $0.isVisible && $0.title == "Digger" })?.contentView {
                        revealScrollers(in: view)
                    }
                    try? await Task.sleep(for: .milliseconds(150))
                }
                guard let window = app.windows.first(where: { $0.isVisible && $0.frame.width > 300 }), let view = window.contentView,
                      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                    print("Unable to render preview"); app.terminate(nil); return
                }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let data = bitmap.representation(using: .png, properties: [:]) {
                    try? data.write(to: URL(fileURLWithPath: path))
                }
                app.terminate(nil)
            }
        }
        withExtendedLifetime((preferences, menuBar, welcome)) { app.run() }
    }
}
#endif
