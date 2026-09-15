import ApplicationServices
import AppKit
import Carbon
import Foundation
import os

final class SelectionHandler: @unchecked Sendable {
    private let systemElement = AXUIElementCreateSystemWide()
    private let triggerLock = OSAllocatedUnfairLock<TimeInterval>(uncheckedState: 0)
    private let extractionLock = OSAllocatedUnfairLock<Bool>(uncheckedState: false)
    private let triggerCooldown: TimeInterval = 0.25
    @MainActor private lazy var popupRunner = PopupFunctionRunner()

    init() {
        Task { @MainActor [weak self] in
            selectionPopup.onRetry = { [weak self] text, anchorLocation in
                guard let self else {
                    return
                }
                Task {
                    self.popupRunner.run(text: text, forceAPI: true, anchorLocation: anchorLocation)
                }
            }
        }
    }

    func handleShortcut() async {
        guard shouldHandleTrigger() else { return }
        let acquired = extractionLock.withLockUnchecked { busy in
            if busy { return false }
            busy = true
            return true
        }
        guard acquired else { return }
        // Read before activating our panel so the source app keeps its selection.
        let selected = fetchSelectedTextOnly()
        let text = Self.readSelection(isWeb: isWebSelection(), accessibilityText: selected,
                                      copy: copySelectionText, word: fetchOrSelectText)
        extractionLock.withLockUnchecked { $0 = false }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("[Digger] No selected text was available through Accessibility or clipboard fallback.")
            await MainActor.run {
                selectionPopup.showNotice(title: localized("No selected text", "没有读取到选中文字", "選択テキストがありません"),
                                          message: localized("Select text in another app, then press your Digger shortcut again. If text is already selected, check Accessibility access for this running build.", "请先在其他应用中选中文字，再按 Digger 快捷键。如果已经选中，请检查当前运行版本的辅助功能权限。", "他のアプリでテキストを選択し、もう一度ショートカットを押してください。選択済みの場合は現在のビルドのアクセシビリティ権限を確認してください。"))
            }
            return
        }
        print("[Digger] Selection read; starting prompt actions.")
        await popupRunner.run(text: text)
    }

    private func shouldHandleTrigger() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        return triggerLock.withLockUnchecked { last in
            if now - last < triggerCooldown {
                return false
            }
            last = now
            return true
        }
    }

    private func fetchSelectedTextOnly() -> String? {
        guard let focusedElementValue = copyAttribute(
            element: systemElement,
            attribute: kAXFocusedUIElementAttribute as CFString
        ) else {
            return nil
        }
        let focusedElement = focusedElementValue as! AXUIElement

        var remainingNodes = 200
        if let selectedText = findSelectedText(in: focusedElement, maxDepth: 4, remainingNodes: &remainingNodes) {
            return selectedText
        }

        if let focusedWindowValue = copyAttribute(
            element: systemElement,
            attribute: kAXFocusedWindowAttribute as CFString
        ) {
            let focusedWindow = focusedWindowValue as! AXUIElement
            remainingNodes = 200
            if let selectedText = findSelectedText(in: focusedWindow, maxDepth: 4, remainingNodes: &remainingNodes) {
                return selectedText
            }
        }

        if let selectedText = copyAttribute(
            element: focusedElement,
            attribute: kAXSelectedTextAttribute as CFString
        ) as? String, !selectedText.isEmpty {
            return selectedText
        }

        return nil
    }

    private func fetchOrSelectText() -> String? {
        guard let focusedElementValue = copyAttribute(
            element: systemElement,
            attribute: kAXFocusedUIElementAttribute as CFString
        ) else {
            return nil
        }
        let focusedElement = focusedElementValue as! AXUIElement

        if let selectedText = fetchSelectedTextOnly(), !selectedText.isEmpty {
            return selectedText
        }

        guard let rangeValueAny = copyAttribute(
            element: focusedElement,
            attribute: kAXSelectedTextRangeAttribute as CFString
        ) else {
            return nil
        }
        let rangeValue = rangeValueAny as! AXValue

        var selectionRange = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &selectionRange) else {
            return nil
        }

        let selectionLocation = selectionRange.location
        var contextText: String?
        var contextBaseLocation = 0

        if let fullText = copyAttribute(
            element: focusedElement,
            attribute: kAXValueAttribute as CFString
        ) as? String, !fullText.isEmpty {
            contextText = fullText
            contextBaseLocation = 0
        } else if let visibleRangeValue = copyAttribute(
            element: focusedElement,
            attribute: kAXVisibleCharacterRangeAttribute as CFString
        ) {
            let axVisibleRange = visibleRangeValue as! AXValue
            var visibleRange = CFRange()
            if AXValueGetValue(axVisibleRange, .cfRange, &visibleRange),
               let visibleRangeValue = AXValueCreate(.cfRange, &visibleRange),
               let visibleText = copyParameterizedAttribute(
                element: focusedElement,
                attribute: kAXStringForRangeParameterizedAttribute as CFString,
                parameter: visibleRangeValue
               ) as? String, !visibleText.isEmpty {
                contextText = visibleText
                contextBaseLocation = visibleRange.location
            }
        }

        guard let contextText, !contextText.isEmpty else {
            return nil
        }

        let nsContext = contextText as NSString
        if selectionRange.length > 0 {
            var selectedRange = selectionRange
            if let axRange = AXValueCreate(.cfRange, &selectedRange),
               let rangeText = copyParameterizedAttribute(
                element: focusedElement,
                attribute: kAXStringForRangeParameterizedAttribute as CFString,
                parameter: axRange
               ) as? String, !rangeText.isEmpty {
                return rangeText
            }
            let localLocation = selectionRange.location - contextBaseLocation
            if localLocation >= 0,
               localLocation + selectionRange.length <= nsContext.length {
                return nsContext.substring(
                    with: NSRange(location: localLocation, length: selectionRange.length)
                )
            }
        }

        let caretIndex = max(0, min(selectionLocation - contextBaseLocation, nsContext.length))
        let wordRange = currentWordRange(in: contextText, caretIndex: caretIndex)
        guard wordRange.length > 0 else {
            return nil
        }

        var adjustedRange = CFRange(
            location: contextBaseLocation + wordRange.location,
            length: wordRange.length
        )
        let axRange = AXValueCreate(.cfRange, &adjustedRange)
        if let axRange,
           let rangeText = copyParameterizedAttribute(
            element: focusedElement,
            attribute: kAXStringForRangeParameterizedAttribute as CFString,
            parameter: axRange
           ) as? String, !rangeText.isEmpty {
            return rangeText
        }

        return nsContext.substring(with: NSRange(location: wordRange.location, length: wordRange.length))
    }


    /// Browser AX text can be flattened even when it is nonempty. Preserve rich copy
    /// ahead of that fallback, while editors keep their verbatim Markdown selection.
    static func readSelection(isWeb: Bool, accessibilityText: String?,
                              copy: () -> String?, word: () -> String?) -> String? {
        if isWeb { return copy() ?? accessibilityText ?? word() }
        return accessibilityText ?? word() ?? copy()
    }

    private func isWebSelection() -> Bool {
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        if ["com.apple.Safari", "com.google.Chrome", "org.chromium.Chromium", "org.mozilla.firefox",
            "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser",
            "com.kagi.kagimacOS", "app.zen-browser.zen"].contains(where: { bundleID == $0 || bundleID.hasPrefix($0 + ".") }) {
            return true
        }
        guard let focused = copyAttribute(element: systemElement, attribute: kAXFocusedUIElementAttribute as CFString) else { return false }
        var node = focused as! AXUIElement
        for _ in 0..<20 {
            if copyAttribute(element: node, attribute: kAXRoleAttribute as CFString) as? String == "AXWebArea" { return true }
            guard let parent = copyAttribute(element: node, attribute: kAXParentAttribute as CFString) else { break }
            node = parent as! AXUIElement
        }
        return false
    }

    private func copySelectionText() -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        let changeCount = pasteboard.changeCount
        let sourcePID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        sendCopyCommand()
        let deadline = ProcessInfo.processInfo.systemUptime + 0.35
        while ProcessInfo.processInfo.systemUptime < deadline {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == sourcePID else { return nil }
            let copiedCount = pasteboard.changeCount
            if copiedCount != changeCount {
                let content = SelectionClipboardContent(pasteboard: pasteboard)
                guard pasteboard.changeCount == copiedCount else { return nil }
                // Restore before parsing. Don't overwrite a newer clipboard owner.
                snapshot.restore(to: pasteboard, ifUnchangedSince: copiedCount)
                if let html = content.html, let markdown = HTMLSelectionMarkdown.convert(html) {
                    print("[Digger] HTML selection converted to Markdown.")
                    return markdown
                }
                if let plain = content.plainText, !plain.isEmpty { return plain }
                return nil
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return nil
    }

    private func sendCopyCommand() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return
        }
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)
    }

}
