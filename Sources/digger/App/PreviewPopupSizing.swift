#if DEBUG
import AppKit

@MainActor
enum PreviewPopupSizing {
    static func run() async {
        let screen = NSScreen.main!.visibleFrame
        let function = PopupFunction(id: UUID(), title: "Translation", prompt: "", isTranslation: true)
        let point = CGPoint(x: screen.midX, y: screen.maxY - 50)
        func settle() async { try? await Task.sleep(for: .milliseconds(350)) }
        func show(source: String, result: String, near: CGPoint? = nil) -> UUID {
            let id = UUID()
            selectionPopup.showLoading(original: source, near: near ?? point, requestID: id, functions: [function])
            selectionPopup.model.update(result, requestID: id, functionID: function.id, phase: .complete)
            return id
        }
        let id = show(source: "Hello", result: "你好")
        await settle()
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.title == "Digger" }) else {
            preconditionFailure("Missing popup")
        }
        let compact = window.frame
        assert(compact.width == 360 && compact.height < 200, "Short result did not fit: \(compact)")
        assert(screen.contains(compact))
        await verifyGrowingViewport(window, requestID: id, functionID: function.id)
        let long = String(repeating: "A long translated paragraph with readable wrapping.\n\n", count: 35)
        selectionPopup.model.update(long, requestID: id, functionID: function.id, phase: .streaming)
        await settle()
        assert(window.frame.height > compact.height + 100, "Long output did not grow")
        assert(window.frame.height <= AppPreferences.popupMaxHeight())
        assert(window.frame.maxY == compact.maxY && window.frame.width == compact.width)
        PreviewStreamLayout.verify(window)
        verifyFollowingBottom(window)
        selectionPopup.model.sections[0].collapsed = true
        selectionPopup.contentVisibilityChanged()
        await settle()
        assert(window.frame.height < 200, "Collapsing a streaming section did not shrink the window")
        selectionPopup.model.sections[0].collapsed = false
        selectionPopup.contentVisibilityChanged()
        await settle()
        assert(window.frame.height > 200)
        selectionPopup.windowWillStartLiveResize(Notification(name: NSWindow.willStartLiveResizeNotification, object: window))
        window.setContentSize(NSSize(width: 450, height: 260))
        let manual = window.frame
        selectionPopup.model.update(long + long, requestID: id, functionID: function.id, phase: .complete)
        await settle()
        assert(window.frame == manual, "Automatic fitting overrode manual resizing")
        _ = show(source: "New", result: "Short")
        await settle()
        assert(window.frame.height < 200 && window.frame.width == 360, "New selection failed to reset fitting")

        let fontID = show(source: "Font sizing", result: "")
        selectionPopup.applyPopupTextSize(24)
        selectionPopup.model.update(String(repeating: "A line of text.\n\n", count: 5), requestID: fontID,
                                    functionID: function.id, phase: .streaming)
        await settle()
        let largeFontHeight = window.frame.height
        selectionPopup.applyPopupTextSize(12)
        await settle()
        assert(window.frame.height < largeFontHeight, "Font reduction did not refit the streaming window")
        selectionPopup.applyPopupTextSize(PopupFontPreferences.load())
        _ = show(source: long, result: "Short")
        await settle()
        selectionPopup.model.originalCollapsed = false
        selectionPopup.contentVisibilityChanged()
        await settle()
        assert(window.frame.height > 200, "Expanded source was not measured")
        selectionPopup.model.originalCollapsed = true
        selectionPopup.contentVisibilityChanged()
        await settle()
        assert(window.frame.height < 200, "Collapsing the source left excess space")

        selectionPopup.dismiss()
        _ = show(source: "Hello", result: "你好", near: CGPoint(x: screen.maxX - 5, y: screen.minY + 30))
        await settle()
        let bottom = window.frame.minY
        let aboveID = selectionPopup.model.requestID!
        await verifyGrowingViewport(window, requestID: aboveID, functionID: function.id, edge: .bottom)
        selectionPopup.model.update(long, requestID: aboveID, functionID: function.id, phase: .complete)
        await settle()
        assert(window.frame.minY == bottom && screen.contains(window.frame), "Upward expansion left the screen")
        verifyFollowingBottom(window)

        AppPreferences.setPopupAutomaticSize(false)
        _ = show(source: "Hello", result: "你好")
        await settle()
        assert(window.frame.width == AppPreferences.popupMaxWidth())
        assert(window.frame.height == AppPreferences.popupMaxHeight(), "Fixed-size mode changed size")
        AppPreferences.setPopupAutomaticSize(true)
        selectionPopup.refreshLayout()
        await settle()
        assert(window.frame.width == 360 && window.frame.height < 200, "Changing sizing mode did not apply")
        let settings = PreferencesViewModel()
        assert(settings.popupAutomaticSize)
        assert(settings.popupMaxWidthText == String(Int(AppPreferences.popupMaxWidth())))
        // Existing saved sizes become limits without being overwritten by defaults.
        AppPreferences.setPopupMaxWidth(520)
        AppPreferences.setPopupMaxHeight(420)
        AppPreferences.defaults.removeObject(forKey: AppPreferences.popupAutomaticSizeKey)
        assert(AppPreferences.popupAutomaticSize())
        assert(AppPreferences.popupMaxWidth() == 520 && AppPreferences.popupMaxHeight() == 420)
        print("[Digger preview] Adaptive sizing, collapse, screen edges, manual resize and fixed mode passed.")
        NSApp.terminate(nil)
    }

    private static func verifyGrowingViewport(_ window: NSWindow, requestID: UUID, functionID: UUID,
                                               edge: PopupSizing.GrowthEdge = .top) async {
        guard let root = window.contentView, let scroll = PreviewStreamLayout.scrollViews(in: root).first,
              let document = scroll.documentView else { preconditionFailure("Missing reading viewport") }
        let anchor = edge == .top ? window.frame.maxY : window.frame.minY
        for lines in 2...9 {
            selectionPopup.model.update(Array(repeating: "A short line of text.", count: lines).joined(separator: "\n\n"),
                                        requestID: requestID, functionID: functionID, phase: .streaming)
            var origins: [CGFloat] = []
            for _ in 0..<40 {
                try? await Task.sleep(for: .milliseconds(5))
                origins.append(scroll.contentView.bounds.minY)
                let currentAnchor = edge == .top ? window.frame.maxY : window.frame.minY
                assert(abs(currentAnchor - anchor) < 0.5, "Adaptive stream moved the window anchor")
            }
            if document.frame.height <= scroll.contentView.bounds.height + 1 {
                assert(origins.allSatisfy { abs($0) < 1 }, "Growing viewport scrolled before fitting: \(origins)")
            }
        }
    }

    private static func verifyFollowingBottom(_ window: NSWindow) {
        guard let root = window.contentView, let scroll = PreviewStreamLayout.scrollViews(in: root).first,
              let document = scroll.documentView else { preconditionFailure("Missing reading viewport") }
        let bottom = max(0, document.frame.height - scroll.contentView.bounds.height)
        assert(bottom > 0, "Fixture must exceed the adaptive height cap")
        assert(abs(scroll.contentView.bounds.minY - bottom) < 1, "Fitted viewport did not resume following the bottom")
    }
}
#endif
