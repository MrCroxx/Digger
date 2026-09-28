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

    func handleShortcut() async {
        guard shouldHandleTrigger() else { return }
        let acquired = extractionLock.withLockUnchecked { busy in
            if busy { return false }
            busy = true
            return true
        }
        guard acquired else { return }
        defer { extractionLock.withLockUnchecked { $0 = false } }
        // Read before activating our panel so the source app keeps its selection.
        let selected = fetchSelectedTextOnly()
        let isWeb = isWebSelection()
        // Editors can implement Copy with no selection as "copy the current line".
        // Do not mistake that line for a selection during the screenshot gesture.
        let skipCopy = !isWeb && selected == nil && hasEmptySelectionRange()
        let text = Self.readSelection(isWeb: isWeb, accessibilityText: selected,
                                      copy: { skipCopy ? nil : self.copySelectionText() },
                                      word: { self.fetchSelectedRangeText() })
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await captureAndTranslate()
            return
        }
        print("[Digger] Selection read; starting prompt actions.")
        await popupRunner.run(text: text)
    }

    @MainActor
    private func captureAndTranslate() async {
        selectionPopup.dismiss()
        do {
            guard let image = try await RegionScreenshot.capture() else { return }
            popupRunner.run(text: localized("Screenshot", "截图", "スクリーンショット"), imagePNG: image)
        } catch {
            selectionPopup.showNotice(title: localized("Screenshot unavailable", "无法截屏", "スクリーンショットを取得できません"),
                                      message: error.localizedDescription)
        }
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

    private func hasEmptySelectionRange() -> Bool {
        guard let focused = copyAttribute(element: systemElement, attribute: kAXFocusedUIElementAttribute as CFString),
              let value = copyAttribute(element: focused as! AXUIElement, attribute: kAXSelectedTextRangeAttribute as CFString) else { return false }
        var range = CFRange()
        return AXValueGetValue(value as! AXValue, .cfRange, &range) && range.length == 0
    }

    private func fetchSelectedRangeText() -> String? {
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

        return nil
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
