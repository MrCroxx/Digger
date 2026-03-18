import ApplicationServices
import AppKit
import Carbon
import Foundation
import os

final class ForceClickSelectionHandler: @unchecked Sendable {
    private struct SelectionContent {
        let plainText: String
        let markdownText: String?
    }

    private let systemElement = AXUIElementCreateSystemWide()
    private let triggerLock = OSAllocatedUnfairLock<TimeInterval>(uncheckedState: 0)
    private let triggerCooldown: TimeInterval = 0.25
    private let selectionCacheLock = OSAllocatedUnfairLock<SelectionSnapshot?>(uncheckedState: nil)
    private let selectionCacheTTL: TimeInterval = 0.8
    private let popupRunner = PopupFunctionRunner()

    init() {
        Task { @MainActor [weak self] in
            forceClickSelectionPopup.onRetry = { [weak self] text, anchorLocation in
                guard let self else {
                    return
                }
                Task {
                    await self.popupRunner.run(text: text, forceAPI: true, anchorLocation: anchorLocation)
                }
            }
        }
    }

    func handleForceClick() async {
        guard shouldHandleTrigger() else {
            return
        }
        if let selectedText = fetchSelectedTextOnly(), !selectedText.isEmpty {
            let copied = copySelectionContent(selectWordIfNeeded: false)
            await runPopup(
                plainText: selectedText,
                markdownText: copied?.markdownText
            )
            return
        }

        if let cachedSelection = consumeSelectionSnapshotIfValid() {
            _ = restoreSelection(cachedSelection)
            let copied = copySelectionContent(selectWordIfNeeded: false)
            var cachedText = cachedSelection.text
            if cachedText.isEmpty {
                cachedText = copied?.plainText ?? ""
            }
            if !cachedText.isEmpty {
                await runPopup(
                    plainText: cachedText,
                    markdownText: copied?.markdownText
                )
                return
            }
        }

        guard let text = fetchOrSelectText(), !text.isEmpty else {
            if let fallbackContent = copySelectionContent(selectWordIfNeeded: shouldSelectWordFallback()) {
                await runPopup(
                    plainText: fallbackContent.plainText,
                    markdownText: fallbackContent.markdownText
                )
            }
            return
        }
        let copied = copySelectionContent(selectWordIfNeeded: false)
        await runPopup(
            plainText: text,
            markdownText: copied?.markdownText
        )
    }

    private func runPopup(
        plainText: String,
        markdownText: String?,
        forceAPI: Bool = false,
        anchorLocation: CGPoint? = nil
    ) async {
        let trimmedPlainText = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPlainText.isEmpty else {
            return
        }
        let trimmedMarkdownText = markdownText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestText = (trimmedMarkdownText?.isEmpty == false) ? trimmedMarkdownText! : trimmedPlainText
        print(trimmedPlainText)
        await popupRunner.run(
            text: requestText,
            originalText: trimmedPlainText,
            forceAPI: forceAPI,
            anchorLocation: anchorLocation
        )
    }

    func cacheSelectionBeforeMouseDown() {
        guard let snapshot = captureSelectionSnapshot() else {
            selectionCacheLock.withLockUnchecked { $0 = nil }
            return
        }
        selectionCacheLock.withLockUnchecked { $0 = snapshot }
    }

    func clearSelectionCache() {
        selectionCacheLock.withLockUnchecked { $0 = nil }
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

    private func shouldSelectWordFallback() -> Bool {
        guard let focusedElementValue = copyAttribute(
            element: systemElement,
            attribute: kAXFocusedUIElementAttribute as CFString
        ) else {
            return true
        }
        let focusedElement = focusedElementValue as! AXUIElement
        guard let rangeValueAny = copyAttribute(
            element: focusedElement,
            attribute: kAXSelectedTextRangeAttribute as CFString
        ) else {
            return true
        }
        let rangeValue = rangeValueAny as! AXValue
        var selectionRange = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &selectionRange) else {
            return true
        }
        return selectionRange.length == 0
    }

    private func consumeSelectionSnapshotIfValid() -> SelectionSnapshot? {
        let now = ProcessInfo.processInfo.systemUptime
        return selectionCacheLock.withLockUnchecked { cache in
            guard let snapshot = cache else {
                return nil
            }
            if now - snapshot.timestamp > selectionCacheTTL {
                cache = nil
                return nil
            }
            cache = nil
            return snapshot
        }
    }

    private func captureSelectionSnapshot() -> SelectionSnapshot? {
        guard let focusedElementValue = copyAttribute(
            element: systemElement,
            attribute: kAXFocusedUIElementAttribute as CFString
        ) else {
            return nil
        }
        let focusedElement = focusedElementValue as! AXUIElement
        var cachedText = ""
        if let selectedText = copyAttribute(
            element: focusedElement,
            attribute: kAXSelectedTextAttribute as CFString
        ) as? String, !selectedText.isEmpty {
            cachedText = selectedText
        }

        guard let rangeValueAny = copyAttribute(
            element: focusedElement,
            attribute: kAXSelectedTextRangeAttribute as CFString
        ) else {
            return cachedText.isEmpty ? nil : SelectionSnapshot(
                element: focusedElement,
                range: nil,
                text: cachedText,
                timestamp: ProcessInfo.processInfo.systemUptime
            )
        }

        let rangeValue = rangeValueAny as! AXValue
        var selectionRange = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &selectionRange), selectionRange.length > 0 else {
            return cachedText.isEmpty ? nil : SelectionSnapshot(
                element: focusedElement,
                range: nil,
                text: cachedText,
                timestamp: ProcessInfo.processInfo.systemUptime
            )
        }

        if cachedText.isEmpty {
            var rangeCopy = selectionRange
            if let axRange = AXValueCreate(.cfRange, &rangeCopy),
               let rangeText = copyParameterizedAttribute(
                element: focusedElement,
                attribute: kAXStringForRangeParameterizedAttribute as CFString,
                parameter: axRange
               ) as? String, !rangeText.isEmpty {
                cachedText = rangeText
            }
        }

        return SelectionSnapshot(
            element: focusedElement,
            range: selectionRange,
            text: cachedText,
            timestamp: ProcessInfo.processInfo.systemUptime
        )
    }

    private func restoreSelection(_ snapshot: SelectionSnapshot) -> Bool {
        guard var range = snapshot.range else {
            return false
        }
        guard let axRange = AXValueCreate(.cfRange, &range) else {
            return false
        }
        let result = AXUIElementSetAttributeValue(
            snapshot.element,
            kAXSelectedTextRangeAttribute as CFString,
            axRange
        )
        return result == .success
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


    private func copySelectionContent(selectWordIfNeeded: Bool) -> SelectionContent? {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        let changeCount = pasteboard.changeCount

        sendCopyCommand()
        var copiedContent = waitForPasteboardContent(
            pasteboard: pasteboard,
            originalChangeCount: changeCount,
            timeout: 0.25
        )

        if copiedContent == nil, selectWordIfNeeded {
            if let location = currentEventTapMouseLocation() ?? currentMouseLocation() {
                performDoubleClick(at: location)
                Thread.sleep(forTimeInterval: 0.06)
                let retryChangeCount = pasteboard.changeCount
                sendCopyCommand()
                copiedContent = waitForPasteboardContent(
                    pasteboard: pasteboard,
                    originalChangeCount: retryChangeCount,
                    timeout: 0.25
                )
            }
        }

        snapshot.restore(to: pasteboard)
        return copiedContent
    }

    private func waitForPasteboardContent(
        pasteboard: NSPasteboard,
        originalChangeCount: Int,
        timeout: TimeInterval
    ) -> SelectionContent? {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            let didChange = pasteboard.changeCount != originalChangeCount
            if didChange, let content = selectionContent(from: pasteboard) {
                return content
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return nil
    }

    private func selectionContent(from pasteboard: NSPasteboard) -> SelectionContent? {
        let plainText = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let markdown = markdownFromPasteboard(pasteboard)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let markdown, !markdown.isEmpty {
            let resolvedPlainText = plainText.isEmpty ? plainTextFromMarkdown(markdown) : plainText
            guard !resolvedPlainText.isEmpty else {
                return nil
            }
            return SelectionContent(plainText: resolvedPlainText, markdownText: markdown)
        }
        guard !plainText.isEmpty else {
            return nil
        }
        return SelectionContent(plainText: plainText, markdownText: nil)
    }

    private func markdownFromPasteboard(_ pasteboard: NSPasteboard) -> String? {
        if let htmlData = pasteboard.data(forType: .html),
           let markdown = markdownFromHTMLData(htmlData) {
            return markdown
        }
        if let rtfData = pasteboard.data(forType: .rtf),
           let markdown = markdownFromRTFData(rtfData) {
            return markdown
        }
        return nil
    }

    private func markdownFromHTMLData(_ data: Data) -> String? {
        guard let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) else {
            return nil
        }
        return markdownFromAttributedString(attributed)
    }

    private func markdownFromRTFData(_ data: Data) -> String? {
        guard let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) else {
            return nil
        }
        return markdownFromAttributedString(attributed)
    }

    private func markdownFromAttributedString(_ attributed: NSAttributedString) -> String? {
        guard attributed.length > 0 else {
            return nil
        }

        var output = ""
        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
            let segment = attributed.attributedSubstring(from: range).string
            guard !segment.isEmpty else {
                return
            }
            let lines = segment.components(separatedBy: "\n")
            for index in lines.indices {
                let line = lines[index]
                if !line.isEmpty {
                    output += styledMarkdownText(line, attributes: attributes)
                }
                if index < lines.count - 1 {
                    output += "\n"
                }
            }
        }

        let normalized = normalizeMarkdownText(output)
        return normalized.isEmpty ? nil : normalized
    }

    private func styledMarkdownText(_ text: String, attributes: [NSAttributedString.Key: Any]) -> String {
        var value = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        let traits = (attributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
        let isBold = traits.contains(.bold)
        let isItalic = traits.contains(.italic)
        if let linkURL = attributes[.link] as? URL {
            value = "[\(value)](\(linkURL.absoluteString))"
        } else if let linkString = attributes[.link] as? String, !linkString.isEmpty {
            value = "[\(value)](\(linkString))"
        }
        if isBold && isItalic {
            return "***\(value)***"
        }
        if isBold {
            return "**\(value)**"
        }
        if isItalic {
            return "*\(value)*"
        }
        return value
    }

    private func normalizeMarkdownText(_ markdown: String) -> String {
        var value = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        value = value.replacingOccurrences(
            of: #"(?m)^\s*[•◦▪]\s*"#,
            with: "- ",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func plainTextFromMarkdown(_ markdown: String) -> String {
        if #available(macOS 13.0, *),
           let attributed = try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
           ) {
            let resolved = String(attributed.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            if !resolved.isEmpty {
                return resolved
            }
        }

        let stripped = markdown.replacingOccurrences(
            of: #"[*_`\[\]#>-]"#,
            with: "",
            options: .regularExpression
        )
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func currentMouseLocation() -> CGPoint? {
        NSEvent.mouseLocation
    }

    private func currentEventTapMouseLocation() -> CGPoint? {
        CGEvent(source: nil)?.location
    }

    private func performDoubleClick(at location: CGPoint) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return
        }

        for clickCount in 1...2 {
            let mouseDown = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDown,
                mouseCursorPosition: location,
                mouseButton: .left
            )
            let mouseUp = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseUp,
                mouseCursorPosition: location,
                mouseButton: .left
            )
            mouseDown?.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
            mouseUp?.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
            mouseDown?.post(tap: .cgSessionEventTap)
            mouseUp?.post(tap: .cgSessionEventTap)
        }
    }
}
