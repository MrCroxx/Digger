import ApplicationServices
import AppKit
import Carbon
import Foundation
import os

final class ForceClickSelectionHandler {
    private let systemElement = AXUIElementCreateSystemWide()
    private let triggerLock = OSAllocatedUnfairLock<TimeInterval>(uncheckedState: 0)
    private let triggerCooldown: TimeInterval = 0.25
    private let selectionCacheLock = OSAllocatedUnfairLock<SelectionSnapshot?>(uncheckedState: nil)
    private let selectionCacheTTL: TimeInterval = 0.8

    func handleForceClick() {
        guard shouldHandleTrigger() else {
            return
        }
        if let selectedText = fetchSelectedTextOnly(), !selectedText.isEmpty {
            print(selectedText)
            translateAndShow(text: selectedText)
            return
        }

        if let cachedSelection = consumeSelectionSnapshotIfValid() {
            _ = restoreSelection(cachedSelection)
            var cachedText = cachedSelection.text
            if cachedText.isEmpty {
                cachedText = copySelectionText(selectWordIfNeeded: false) ?? ""
            }
            if !cachedText.isEmpty {
                print(cachedText)
                translateAndShow(text: cachedText)
                return
            }
        }

        guard let text = fetchOrSelectText(), !text.isEmpty else {
            if let fallbackText = copySelectionText(selectWordIfNeeded: shouldSelectWordFallback()),
               !fallbackText.isEmpty {
                print(fallbackText)
                translateAndShow(text: fallbackText)
            }
            return
        }
        print(text)
        translateAndShow(text: text)
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

    private func translateAndShow(text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }
        guard let location = currentMouseLocation() else {
            return
        }
        let requestID = UUID()
        Task { @MainActor in
            forceClickSelectionPopup.showLoading(original: trimmedText, near: location, requestID: requestID)
        }
        Task { [trimmedText, location, requestID] in
            let translation: String
            if let translator = OpenAITranslator() {
                do {
                    let result = try await translator.translate(trimmedText)
                    translation = result.isEmpty ? UIStrings.Translation.emptyResult : result
                } catch {
                    translation = UIStrings.Translation.failed
                }
            } else {
                translation = UIStrings.Translation.missingApiKey
            }
            print("\(UIStrings.Translation.printPrefix) \(translation)")
            await MainActor.run {
                forceClickSelectionPopup.updateTranslation(translation, for: requestID, near: location)
            }
        }
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

    private func copySelectionText(selectWordIfNeeded: Bool) -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        let changeCount = pasteboard.changeCount

        sendCopyCommand()
        var copiedText = waitForPasteboardText(
            pasteboard: pasteboard,
            originalChangeCount: changeCount,
            timeout: 0.25
        )

        if copiedText == nil, selectWordIfNeeded {
            if let location = currentEventTapMouseLocation() ?? currentMouseLocation() {
                performDoubleClick(at: location)
                Thread.sleep(forTimeInterval: 0.06)
                let retryChangeCount = pasteboard.changeCount
                sendCopyCommand()
                copiedText = waitForPasteboardText(
                    pasteboard: pasteboard,
                    originalChangeCount: retryChangeCount,
                    timeout: 0.25
                )
            }
        }

        snapshot.restore(to: pasteboard)
        return copiedText
    }

    private func waitForPasteboardText(
        pasteboard: NSPasteboard,
        originalChangeCount: Int,
        timeout: TimeInterval
    ) -> String? {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            let didChange = pasteboard.changeCount != originalChangeCount
            if didChange,
               let text = pasteboard.string(forType: .string),
               !text.isEmpty {
                return text
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
