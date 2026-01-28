import ApplicationServices
import AppKit
import Carbon
import Foundation
import OpenMultitouchSupport
import OpenAI
import os

private final class ForceClickMonitor {
    private let settingsLock = OSAllocatedUnfairLock<(Float, Float, TimeInterval)>(uncheckedState: (0, 0, 0))
    private let onForceClick: () -> Void
    private let activeLock = OSAllocatedUnfairLock<Bool>(uncheckedState: false)
    private let mouseDownLock = OSAllocatedUnfairLock<Bool>(uncheckedState: false)
    private let baselineLock = OSAllocatedUnfairLock<Float>(uncheckedState: 0)
    private let downTimeLock = OSAllocatedUnfairLock<TimeInterval?>(uncheckedState: nil)
    private var hasForceClicked = false

    init(
        pressureThreshold: Float,
        pressureDelta: Float,
        baselineWindow: TimeInterval,
        onForceClick: @escaping () -> Void
    ) {
        settingsLock.withLockUnchecked { settings in
            settings = (pressureThreshold, pressureDelta, baselineWindow)
        }
        self.onForceClick = onForceClick
    }

    func updateSettings(pressureThreshold: Float, pressureDelta: Float, baselineWindow: TimeInterval) {
        settingsLock.withLockUnchecked { settings in
            settings = (pressureThreshold, pressureDelta, baselineWindow)
        }
    }

    func setMouseDown(_ isDown: Bool) {
        mouseDownLock.withLockUnchecked { $0 = isDown }
        if isDown {
            downTimeLock.withLockUnchecked { $0 = ProcessInfo.processInfo.systemUptime }
            baselineLock.withLockUnchecked { $0 = 0 }
            hasForceClicked = false
            activeLock.withLockUnchecked { $0 = false }
        } else {
            downTimeLock.withLockUnchecked { $0 = nil }
            baselineLock.withLockUnchecked { $0 = 0 }
            hasForceClicked = false
            activeLock.withLockUnchecked { $0 = false }
        }
    }

    func update(touches: [OMSTouchData]) {
        let isMouseDown = mouseDownLock.withLockUnchecked { $0 }
        if !isMouseDown {
            activeLock.withLockUnchecked { $0 = false }
            return
        }

        if hasForceClicked {
            activeLock.withLockUnchecked { $0 = true }
            return
        }

        guard let downTime = downTimeLock.withLockUnchecked({ $0 }) else {
            return
        }

        let (pressureThreshold, pressureDelta, baselineWindow) = settingsLock.withLockUnchecked { $0 }
        let elapsed = ProcessInfo.processInfo.systemUptime - downTime
        var shouldTrigger = false

        for touch in touches {
            switch touch.state {
            case .making, .touching, .breaking, .lingering:
                if elapsed < baselineWindow {
                    baselineLock.withLockUnchecked { baseline in
                        if touch.pressure > baseline {
                            baseline = touch.pressure
                        }
                    }
                } else {
                    let baseline = baselineLock.withLockUnchecked { $0 }
                    let dynamicThreshold = max(pressureThreshold, baseline + pressureDelta)
                    if touch.pressure >= dynamicThreshold {
                        shouldTrigger = true
                    }
                }
            case .notTouching, .starting, .hovering, .leaving:
                break
            }
        }

        if shouldTrigger {
            hasForceClicked = true
            activeLock.withLockUnchecked { $0 = true }
            print("Force click detected")
            onForceClick()
        }
    }

    func shouldSuppressEvents() -> Bool {
        activeLock.withLockUnchecked { $0 }
    }
}

private actor OpenAITranslator {
    private let client: OpenAI

    init?() {
        let token = AppPreferences.apiKey()
        guard !token.isEmpty else {
            return nil
        }

        var host = "api.openai.com"
        var basePath = "/v1"
        var port = 443
        var scheme = "https"
        let endpointText = AppPreferences.endpoint()
        if !endpointText.isEmpty,
           let endpoint = URL(string: endpointText) {
            if let endpointHost = endpoint.host {
                host = endpointHost
            }
            if !endpoint.path.isEmpty {
                basePath = endpoint.path
            }
            if let endpointScheme = endpoint.scheme {
                scheme = endpointScheme
            }
            if let endpointPort = endpoint.port {
                port = endpointPort
            }
        }

        let configuration = OpenAI.Configuration(
            token: token,
            host: host,
            port: port,
            scheme: scheme,
            basePath: basePath,
            parsingOptions: .relaxed
        )

        client = OpenAI(configuration: configuration)
    }

    func translate(_ text: String) async throws -> String {
        let query = ChatQuery(
            messages: [
                .system(.init(content: .textContent("Translate the user's text into Simplified Chinese. Preserve meaning, formatting, and proper nouns."))),
                .user(.init(content: .string(text)))
            ],
            model: .gpt4_1_mini,
            temperature: 0.2
        )
        let result = try await client.chats(query: query)
        return result.choices.first?.message.content?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
    }
}

private final class ForceClickSelectionHandler {
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

private struct SelectionSnapshot {
    let element: AXUIElement
    let range: CFRange?
    let text: String
    let timestamp: TimeInterval
}

private final class DraggableContentView: NSView {
    override var mouseDownCanMoveWindow: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point)
    }
}

private final class DraggableScrollView: NSScrollView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

@MainActor
private final class ForceClickSelectionPopup {
    private let window: PopupWindow
    private let originalTitleField: NSTextField
    private let originalTextField: NSTextField
    private let translationTitleField: NSTextField
    private let translationTextField: NSTextField
    private let loadingTextField: NSTextField
    private let dividerView: NSView
    private let contentView: DraggableContentView
    private let scrollView: DraggableScrollView
    private let documentView: NSView
    private var loadingTimer: Timer?
    private var loadingDotCount = 0
    private var currentRequestID: UUID?
    private var lastAnchorLocation: CGPoint?
    private var isShowingTranslation = false
    private var isShowingLoading = false
    private let baseTitleSize: CGFloat = 11
    private let baseTextSize: CGFloat = 12
    private let baseLoadingSize: CGFloat = 11

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        originalTitleField = NSTextField(labelWithString: "")
        originalTitleField.font = NSFont.systemFont(ofSize: baseTitleSize, weight: .semibold)
        originalTitleField.textColor = .secondaryLabelColor
        originalTitleField.backgroundColor = .clear
        originalTitleField.isEditable = false
        originalTitleField.isSelectable = false

        originalTextField = NSTextField(labelWithString: "")
        originalTextField.font = NSFont.systemFont(ofSize: baseTextSize, weight: .medium)
        originalTextField.textColor = .labelColor
        originalTextField.backgroundColor = .clear
        originalTextField.isEditable = false
        originalTextField.isSelectable = false
        originalTextField.lineBreakMode = .byWordWrapping
        originalTextField.maximumNumberOfLines = 0
        originalTextField.cell?.wraps = true
        originalTextField.cell?.usesSingleLineMode = false

        translationTitleField = NSTextField(labelWithString: "")
        translationTitleField.font = NSFont.systemFont(ofSize: baseTitleSize, weight: .semibold)
        translationTitleField.textColor = .secondaryLabelColor
        translationTitleField.backgroundColor = .clear
        translationTitleField.isEditable = false
        translationTitleField.isSelectable = false

        translationTextField = NSTextField(labelWithString: "")
        translationTextField.font = NSFont.systemFont(ofSize: baseTextSize, weight: .medium)
        translationTextField.textColor = .labelColor
        translationTextField.backgroundColor = .clear
        translationTextField.isEditable = false
        translationTextField.isSelectable = false
        translationTextField.lineBreakMode = .byWordWrapping
        translationTextField.maximumNumberOfLines = 0
        translationTextField.cell?.wraps = true
        translationTextField.cell?.usesSingleLineMode = false

        loadingTextField = NSTextField(labelWithString: "")
        loadingTextField.font = NSFont.systemFont(ofSize: baseLoadingSize, weight: .regular)
        loadingTextField.textColor = .secondaryLabelColor
        loadingTextField.backgroundColor = .clear
        loadingTextField.isEditable = false
        loadingTextField.isSelectable = false
        loadingTextField.lineBreakMode = .byTruncatingTail

        dividerView = NSView()
        dividerView.wantsLayer = true
        dividerView.layer?.backgroundColor = NSColor.separatorColor.cgColor

        contentView = DraggableContentView()
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor
        contentView.layer?.cornerRadius = 8
        documentView = NSView()
        documentView.addSubview(originalTitleField)
        documentView.addSubview(originalTextField)
        documentView.addSubview(dividerView)
        documentView.addSubview(translationTitleField)
        documentView.addSubview(translationTextField)
        documentView.addSubview(loadingTextField)

        scrollView = DraggableScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.documentView = documentView
        contentView.addSubview(scrollView)

        window = PopupWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .transient]
        window.ignoresMouseEvents = false
        window.contentView = contentView
        window.onDismiss = { [weak window] in
            window?.orderOut(nil)
        }

        applyPopupTextSize(PopupFontPreferences.load())
        applyStrings()
    }

    func showLoading(original: String, near location: CGPoint, requestID: UUID) {
        let trimmedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOriginal.isEmpty else {
            return
        }

        currentRequestID = requestID
        lastAnchorLocation = location
        isShowingTranslation = false
        isShowingLoading = true
        originalTextField.stringValue = trimmedOriginal
        translationTextField.stringValue = ""
        startLoadingAnimation()
        let contentSize = layoutContent(showTranslation: isShowingTranslation, showLoading: isShowingLoading, near: location)
        setWindowFrame(contentSize: contentSize, near: location, animated: false)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func updateTranslation(_ translation: String, for requestID: UUID, near location: CGPoint) {
        guard currentRequestID == requestID else {
            return
        }
        stopLoadingAnimation()
        let trimmedTranslation = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        lastAnchorLocation = location
        isShowingTranslation = true
        isShowingLoading = false
        translationTextField.stringValue = trimmedTranslation
        let contentSize = layoutContent(showTranslation: isShowingTranslation, showLoading: isShowingLoading, near: location)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            setWindowFrame(contentSize: contentSize, near: location, animated: true)
        }
    }

    func show(original: String, translation: String, near location: CGPoint) {
        let trimmedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTranslation = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOriginal.isEmpty else {
            return
        }

        currentRequestID = UUID()
        stopLoadingAnimation()
        lastAnchorLocation = location
        isShowingTranslation = true
        isShowingLoading = false
        originalTextField.stringValue = trimmedOriginal
        translationTextField.stringValue = trimmedTranslation
        let contentSize = layoutContent(showTranslation: isShowingTranslation, showLoading: isShowingLoading, near: location)
        setWindowFrame(contentSize: contentSize, near: location, animated: false)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func applyPopupTextSize(_ textSize: CGFloat) {
        let clampedSize = PopupFontPreferences.clamp(textSize)
        let scale = clampedSize / baseTextSize
        originalTitleField.font = NSFont.systemFont(ofSize: baseTitleSize * scale, weight: .semibold)
        originalTextField.font = NSFont.systemFont(ofSize: baseTextSize * scale, weight: .medium)
        translationTitleField.font = NSFont.systemFont(ofSize: baseTitleSize * scale, weight: .semibold)
        translationTextField.font = NSFont.systemFont(ofSize: baseTextSize * scale, weight: .medium)
        loadingTextField.font = NSFont.systemFont(ofSize: baseLoadingSize * scale, weight: .regular)

        if window.isVisible, let location = lastAnchorLocation {
            let contentSize = layoutContent(showTranslation: isShowingTranslation, showLoading: isShowingLoading, near: location)
            setWindowFrame(contentSize: contentSize, near: location, animated: false)
        }
    }

    func applyStrings() {
        originalTitleField.stringValue = UIStrings.Popup.originalTitle
        translationTitleField.stringValue = UIStrings.Popup.translationTitle
        if isShowingLoading {
            updateLoadingText()
        }
    }

    func refreshLayout() {
        guard window.isVisible, let location = lastAnchorLocation else {
            return
        }
        let contentSize = layoutContent(showTranslation: isShowingTranslation, showLoading: isShowingLoading, near: location)
        setWindowFrame(contentSize: contentSize, near: location, animated: false)
    }

    private func layoutContent(showTranslation: Bool, showLoading: Bool, near location: CGPoint?) -> CGSize {
        dividerView.isHidden = !showTranslation
        translationTitleField.isHidden = !showTranslation
        translationTextField.isHidden = !showTranslation
        loadingTextField.isHidden = !showLoading

        let padding = CGSize(width: 10, height: 8)
        let minWidth: CGFloat = 120
        let baseMaxWidth: CGFloat = 320
        let preferredMaxWidth = AppPreferences.popupMaxWidth()
        let preferredMaxHeight = AppPreferences.popupMaxHeight()
        let screen = location.flatMap { screenContaining($0) } ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? .zero
        let maxWidthLimit = max(minWidth, min(preferredMaxWidth, visibleFrame.width - 24))
        let maxHeightLimit = max(120, min(preferredMaxHeight, visibleFrame.height - 24))
        let titleTextSpacing: CGFloat = 2
        let dividerHeight: CGFloat = 1
        let dividerSpacing: CGFloat = 6
        let loadingSpacing: CGFloat = 6
        let scrollerClearance: CGFloat = 12
        let paddingLeft = padding.width

        func textSize(for textField: NSTextField, maxWidth: CGFloat) -> CGSize {
            let font = textField.font ?? NSFont.systemFont(ofSize: 12, weight: .medium)
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let attributed = NSAttributedString(string: textField.stringValue, attributes: attributes)
            let boundingRect = attributed.boundingRect(
                with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            return CGSize(width: ceil(boundingRect.width), height: ceil(boundingRect.height) + 4)
        }

        let titleFont = originalTitleField.font ?? NSFont.systemFont(ofSize: 11, weight: .semibold)
        let titleAttributes: [NSAttributedString.Key: Any] = [.font: titleFont]

        func measureLayout(maxWidth: CGFloat, paddingRight: CGFloat) -> (contentWidth: CGFloat, contentHeight: CGFloat, sizes: (CGSize, CGSize, CGSize, CGSize, CGSize)) {
            let originalTitleSize = (originalTitleField.stringValue as NSString).size(withAttributes: titleAttributes)
            let translationTitleSize = (translationTitleField.stringValue as NSString).size(withAttributes: titleAttributes)
            let textMaxWidth = maxWidth - paddingLeft - paddingRight
            let originalTextSize = textSize(for: originalTextField, maxWidth: textMaxWidth)
            let translationTextSize = textSize(for: translationTextField, maxWidth: textMaxWidth)
            let loadingTextSize = textSize(for: loadingTextField, maxWidth: textMaxWidth)

            let contentTextWidth = max(
                originalTitleSize.width,
                originalTextSize.width,
                showTranslation ? max(translationTitleSize.width, translationTextSize.width) : 0,
                showLoading ? loadingTextSize.width : 0
            )
            let contentWidth = max(minWidth, min(maxWidth, contentTextWidth + paddingLeft + paddingRight))
            let adjustedTextMaxWidth = contentWidth - paddingLeft - paddingRight
            if abs(adjustedTextMaxWidth - textMaxWidth) > 0.5 {
                let adjustedOriginalTextSize = textSize(for: originalTextField, maxWidth: adjustedTextMaxWidth)
                let adjustedTranslationTextSize = textSize(for: translationTextField, maxWidth: adjustedTextMaxWidth)
                let adjustedLoadingTextSize = textSize(for: loadingTextField, maxWidth: adjustedTextMaxWidth)
                return (
                    contentWidth,
                    contentHeight(
                        originalTitleSize: originalTitleSize,
                        translationTitleSize: translationTitleSize,
                        originalTextSize: adjustedOriginalTextSize,
                        translationTextSize: adjustedTranslationTextSize,
                        loadingTextSize: adjustedLoadingTextSize,
                        titleTextSpacing: titleTextSpacing,
                        dividerHeight: dividerHeight,
                        dividerSpacing: dividerSpacing,
                        loadingSpacing: loadingSpacing,
                        padding: padding,
                        showTranslation: showTranslation,
                        showLoading: showLoading
                    ),
                    (originalTitleSize, translationTitleSize, adjustedOriginalTextSize, adjustedTranslationTextSize, adjustedLoadingTextSize)
                )
            }

            let height = contentHeight(
                originalTitleSize: originalTitleSize,
                translationTitleSize: translationTitleSize,
                originalTextSize: originalTextSize,
                translationTextSize: translationTextSize,
                loadingTextSize: loadingTextSize,
                titleTextSpacing: titleTextSpacing,
                dividerHeight: dividerHeight,
                dividerSpacing: dividerSpacing,
                loadingSpacing: loadingSpacing,
                padding: padding,
                showTranslation: showTranslation,
                showLoading: showLoading
            )
            return (contentWidth, height, (originalTitleSize, translationTitleSize, originalTextSize, translationTextSize, loadingTextSize))
        }

        func contentHeight(
            originalTitleSize: CGSize,
            translationTitleSize: CGSize,
            originalTextSize: CGSize,
            translationTextSize: CGSize,
            loadingTextSize: CGSize,
            titleTextSpacing: CGFloat,
            dividerHeight: CGFloat,
            dividerSpacing: CGFloat,
            loadingSpacing: CGFloat,
            padding: CGSize,
            showTranslation: Bool,
            showLoading: Bool
        ) -> CGFloat {
            let originalTitleHeight = ceil(originalTitleSize.height)
            let translationTitleHeight = ceil(translationTitleSize.height)
            let originalTextHeight = max(ceil(originalTextSize.height), 16)
            let translationTextHeight = max(ceil(translationTextSize.height), 16)
            let loadingTextHeight = max(ceil(loadingTextSize.height), 14)
            return padding.height * 2 + 4
                + originalTitleHeight
                + titleTextSpacing
                + originalTextHeight
                + (showLoading ? (loadingSpacing + loadingTextHeight) : 0)
                + (showTranslation
                    ? (dividerSpacing
                        + dividerHeight
                        + dividerSpacing
                        + translationTitleHeight
                        + titleTextSpacing
                        + translationTextHeight)
                    : 0)
        }

        var paddingRight = padding.width
        var targetMaxWidth = min(baseMaxWidth, maxWidthLimit)
        var measurement = measureLayout(maxWidth: targetMaxWidth, paddingRight: paddingRight)
        let widthStep: CGFloat = 40
        while measurement.contentHeight > maxHeightLimit && targetMaxWidth < maxWidthLimit {
            targetMaxWidth = min(targetMaxWidth + widthStep, maxWidthLimit)
            measurement = measureLayout(maxWidth: targetMaxWidth, paddingRight: paddingRight)
        }

        let needsVerticalScroll = measurement.contentHeight > maxHeightLimit
        if needsVerticalScroll {
            paddingRight = padding.width + scrollerClearance
            targetMaxWidth = min(targetMaxWidth, maxWidthLimit)
            measurement = measureLayout(maxWidth: targetMaxWidth, paddingRight: paddingRight)
            while measurement.contentHeight > maxHeightLimit && targetMaxWidth < maxWidthLimit {
                targetMaxWidth = min(targetMaxWidth + widthStep, maxWidthLimit)
                measurement = measureLayout(maxWidth: targetMaxWidth, paddingRight: paddingRight)
            }
        }

        let contentWidth = measurement.contentWidth
        let originalTitleSize = measurement.sizes.0
        let translationTitleSize = measurement.sizes.1
        let originalTextSize = measurement.sizes.2
        let translationTextSize = measurement.sizes.3
        let loadingTextSize = measurement.sizes.4
        let contentHeight = measurement.contentHeight
        let visibleHeight = min(contentHeight, maxHeightLimit)

        let titleX = paddingLeft
        let textX = paddingLeft
        let availableWidth = contentWidth - paddingLeft - paddingRight
        originalTextField.preferredMaxLayoutWidth = availableWidth
        translationTextField.preferredMaxLayoutWidth = availableWidth

        var y = contentHeight - padding.height - ceil(originalTitleSize.height)

        originalTitleField.frame = NSRect(
            x: titleX,
            y: y,
            width: availableWidth,
            height: ceil(originalTitleSize.height)
        )
        y -= titleTextSpacing + max(ceil(originalTextSize.height), 16)

        originalTextField.frame = NSRect(
            x: textX,
            y: y,
            width: availableWidth,
            height: max(ceil(originalTextSize.height), 16)
        )
        if showLoading {
            y -= loadingSpacing + max(ceil(loadingTextSize.height), 14)
            loadingTextField.frame = NSRect(
                x: textX,
                y: y,
                width: availableWidth,
                height: max(ceil(loadingTextSize.height), 14)
            )
        }

        if showTranslation {
            y -= dividerSpacing + dividerHeight

            dividerView.frame = NSRect(
                x: paddingLeft,
                y: y,
                width: availableWidth,
                height: dividerHeight
            )
            y -= dividerSpacing + ceil(translationTitleSize.height)

            translationTitleField.frame = NSRect(
                x: titleX,
                y: y,
                width: availableWidth,
                height: ceil(translationTitleSize.height)
            )
            y -= titleTextSpacing + max(ceil(translationTextSize.height), 16)

            translationTextField.frame = NSRect(
                x: textX,
                y: y,
                width: availableWidth,
                height: max(ceil(translationTextSize.height), 16)
            )
        }

        let documentSize = CGSize(width: contentWidth, height: contentHeight)
        let visibleSize = CGSize(width: contentWidth, height: visibleHeight)
        documentView.frame = NSRect(origin: .zero, size: documentSize)
        contentView.frame = NSRect(origin: .zero, size: visibleSize)
        scrollView.frame = contentView.bounds
        scrollView.hasVerticalScroller = needsVerticalScroll
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(0, contentHeight - visibleHeight)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        return visibleSize
    }

    private func setWindowFrame(contentSize: CGSize, near location: CGPoint, animated: Bool) {
        let offset = CGPoint(x: 12, y: -12)
        let origin = CGPoint(
            x: location.x + offset.x,
            y: location.y - contentSize.height + offset.y
        )
        let clampedOrigin = clampOrigin(origin, for: contentSize, near: location)
        let frame = NSRect(origin: clampedOrigin, size: contentSize)
        if animated {
            window.animator().setFrame(frame, display: true)
        } else {
            window.setFrame(frame, display: true)
        }
    }

    private func startLoadingAnimation() {
        stopLoadingAnimation()
        loadingDotCount = 0
        updateLoadingText()
        loadingTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickLoadingAnimation()
            }
        }
    }

    private func stopLoadingAnimation() {
        loadingTimer?.invalidate()
        loadingTimer = nil
        loadingDotCount = 0
    }

    private func tickLoadingAnimation() {
        loadingDotCount = (loadingDotCount + 1) % 4
        updateLoadingText()
    }

    private func updateLoadingText() {
        let dots = String(repeating: "·", count: loadingDotCount)
        loadingTextField.stringValue = UIStrings.Translation.loadingPrefix + dots
    }

    private func ensureMonitors() {}

    private func clampOrigin(_ origin: CGPoint, for size: CGSize, near location: CGPoint) -> CGPoint {
        guard let screen = screenContaining(location) ?? NSScreen.main ?? NSScreen.screens.first else {
            return origin
        }

        let visibleFrame = screen.visibleFrame
        let padding: CGFloat = 6
        var x = origin.x
        var y = origin.y

        if x + size.width > visibleFrame.maxX {
            x = visibleFrame.maxX - size.width - padding
        }
        if x < visibleFrame.minX {
            x = visibleFrame.minX + padding
        }
        if y + size.height > visibleFrame.maxY {
            y = visibleFrame.maxY - size.height - padding
        }
        if y < visibleFrame.minY {
            y = visibleFrame.minY + padding
        }

        return CGPoint(x: x, y: y)
    }

    private func screenContaining(_ location: CGPoint) -> NSScreen? {
        for screen in NSScreen.screens where screen.frame.contains(location) {
            return screen
        }
        return nil
    }

    func dismissOnEscape() {
        guard window.isVisible else {
            return
        }
        stopLoadingAnimation()
        window.orderOut(nil)
    }

    func dismissIfClickOutside(_ location: CGPoint) {
        guard window.isVisible else {
            return
        }
        if !isLocationInsideWindow(location) {
            stopLoadingAnimation()
            window.orderOut(nil)
        }
    }

    private func isLocationInsideWindow(_ location: CGPoint) -> Bool {
        let windowNumberAtPoint = NSWindow.windowNumber(
            at: location,
            belowWindowWithWindowNumber: 0
        )
        if windowNumberAtPoint == window.windowNumber {
            return true
        }
        if let contentView = window.contentView {
            let windowPoint = window.convertPoint(fromScreen: location)
            return contentView.bounds.contains(windowPoint)
        }
        return window.frame.contains(location)
    }
}

private final class PopupWindow: NSWindow {
    var onDismiss: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == CGKeyCode(kVK_Escape) {
            onDismiss?()
            return
        }
        super.keyDown(with: event)
    }

}

private enum PopupFontPreferences {
    static let key = "PopupFontSize"
    static let defaultSize: CGFloat = 12
    static let minSize: CGFloat = 10
    static let maxSize: CGFloat = 20

    static func load() -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: key)
        if stored <= 0 {
            return defaultSize
        }
        return clamp(CGFloat(stored))
    }

    static func save(_ size: CGFloat) {
        UserDefaults.standard.set(Double(clamp(size)), forKey: key)
    }

    static func clamp(_ size: CGFloat) -> CGFloat {
        let rounded = size.rounded()
        return min(max(rounded, minSize), maxSize)
    }

    static func format(_ size: CGFloat) -> String {
        "\(Int(size.rounded())) pt"
    }
}

enum AppPreferences {
    static let apiKeyKey = "OpenAIAPIKey"
    static let endpointKey = "OpenAIEndpoint"
    static let pressureThresholdKey = "ForceClickPressureThreshold"
    static let pressureDeltaKey = "ForceClickPressureDelta"
    static let baselineWindowKey = "ForceClickBaselineWindowMs"
    static let popupMaxWidthKey = "PopupMaxWidth"
    static let popupMaxHeightKey = "PopupMaxHeight"
    static let languageKey = "AppLanguage"

    static let defaultThreshold: CGFloat = 3.0
    static let defaultDelta: CGFloat = 2.0
    static let defaultBaselineWindowMs: CGFloat = 120
    static let defaultPopupMaxWidth: CGFloat = 520
    static let defaultPopupMaxHeight: CGFloat = 360
    static let defaultLanguage: AppLanguage = .english

    static func apiKey() -> String {
        UserDefaults.standard.string(forKey: apiKeyKey) ?? ""
    }

    static func setApiKey(_ value: String) {
        UserDefaults.standard.set(value, forKey: apiKeyKey)
    }

    static func endpoint() -> String {
        UserDefaults.standard.string(forKey: endpointKey) ?? ""
    }

    static func setEndpoint(_ value: String) {
        UserDefaults.standard.set(value, forKey: endpointKey)
    }

    static func pressureThreshold() -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: pressureThresholdKey)
        return stored > 0 ? CGFloat(stored) : defaultThreshold
    }

    static func setPressureThreshold(_ value: CGFloat) {
        UserDefaults.standard.set(Double(max(value, 0.1)), forKey: pressureThresholdKey)
    }

    static func pressureDelta() -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: pressureDeltaKey)
        return stored > 0 ? CGFloat(stored) : defaultDelta
    }

    static func setPressureDelta(_ value: CGFloat) {
        UserDefaults.standard.set(Double(max(value, 0.1)), forKey: pressureDeltaKey)
    }

    static func baselineWindowMs() -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: baselineWindowKey)
        return stored > 0 ? CGFloat(stored) : defaultBaselineWindowMs
    }

    static func setBaselineWindowMs(_ value: CGFloat) {
        UserDefaults.standard.set(Double(max(value, 10)), forKey: baselineWindowKey)
    }

    static func popupMaxWidth() -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: popupMaxWidthKey)
        return stored > 0 ? CGFloat(stored) : defaultPopupMaxWidth
    }

    static func setPopupMaxWidth(_ value: CGFloat) {
        UserDefaults.standard.set(Double(max(value, 200)), forKey: popupMaxWidthKey)
    }

    static func popupMaxHeight() -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: popupMaxHeightKey)
        return stored > 0 ? CGFloat(stored) : defaultPopupMaxHeight
    }

    static func setPopupMaxHeight(_ value: CGFloat) {
        UserDefaults.standard.set(Double(max(value, 120)), forKey: popupMaxHeightKey)
    }

    static func language() -> AppLanguage {
        let stored = UserDefaults.standard.string(forKey: languageKey)
        return AppLanguage(rawValue: stored ?? "") ?? defaultLanguage
    }

    static func setLanguage(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: languageKey)
    }
}

@MainActor
private final class PreferencesWindowController: NSObject {
    private let window: NSWindow
    private let titleField: NSTextField
    private let descriptionField: NSTextField
    private let apiKeyField: NSSecureTextField
    private let endpointField: NSTextField
    private let thresholdField: NSTextField
    private let deltaField: NSTextField
    private let windowField: NSTextField
    private let popupMaxWidthField: NSTextField
    private let popupMaxHeightField: NSTextField
    private let popupFontSizeLabelField: NSTextField
    private let languageLabelField: NSTextField
    private let languagePopUp: NSPopUpButton
    private let popupFontSizeSlider: NSSlider
    private let popupFontSizeValueField: NSTextField
    private let onPopupFontSizeChange: (CGFloat) -> Void
    private let onPopupLayoutChange: () -> Void
    private let onLanguageChange: () -> Void
    private let onForceClickSettingsChange: (Float, Float, TimeInterval) -> Void

    init(
        onPopupFontSizeChange: @escaping (CGFloat) -> Void,
        onPopupLayoutChange: @escaping () -> Void,
        onLanguageChange: @escaping () -> Void,
        onForceClickSettingsChange: @escaping (Float, Float, TimeInterval) -> Void
    ) {
        self.onPopupFontSizeChange = onPopupFontSizeChange
        self.onPopupLayoutChange = onPopupLayoutChange
        self.onLanguageChange = onLanguageChange
        self.onForceClickSettingsChange = onForceClickSettingsChange
        NSApplication.shared.activate(ignoringOtherApps: true)
        let contentView = NSView()
        contentView.wantsLayer = true

        titleField = NSTextField(labelWithString: UIStrings.Preferences.title)
        titleField.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        titleField.textColor = .labelColor

        descriptionField = NSTextField(wrappingLabelWithString: UIStrings.Preferences.description)
        descriptionField.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        descriptionField.textColor = .secondaryLabelColor

        apiKeyField = NSSecureTextField()
        apiKeyField.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        apiKeyField.placeholderString = "sk-..."
        apiKeyField.isEditable = true
        apiKeyField.isSelectable = true
        apiKeyField.isBordered = true
        apiKeyField.focusRingType = .default
        endpointField = NSTextField()
        endpointField.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        endpointField.placeholderString = "https://api.openai.com/v1"
        endpointField.isEditable = true
        endpointField.isSelectable = true
        thresholdField = NSTextField()
        thresholdField.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        thresholdField.isEditable = true
        thresholdField.isSelectable = true
        deltaField = NSTextField()
        deltaField.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        deltaField.isEditable = true
        deltaField.isSelectable = true
        windowField = NSTextField()
        windowField.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        windowField.isEditable = true
        windowField.isSelectable = true
        popupMaxWidthField = NSTextField()
        popupMaxWidthField.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        popupMaxWidthField.isEditable = true
        popupMaxWidthField.isSelectable = true
        popupMaxHeightField = NSTextField()
        popupMaxHeightField.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        popupMaxHeightField.isEditable = true
        popupMaxHeightField.isSelectable = true
        popupFontSizeLabelField = NSTextField(labelWithString: UIStrings.Preferences.popupFontSizeLabel)
        popupFontSizeLabelField.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        popupFontSizeLabelField.textColor = .secondaryLabelColor
        languageLabelField = NSTextField(labelWithString: UIStrings.Preferences.languageLabel)
        languageLabelField.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        languageLabelField.textColor = .secondaryLabelColor
        languagePopUp = NSPopUpButton()
        languagePopUp.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        languagePopUp.isBordered = true
        for (index, language) in AppLanguage.allCases.enumerated() {
            languagePopUp.addItem(withTitle: language.displayName)
            languagePopUp.item(at: index)?.representedObject = language.rawValue
        }
        popupFontSizeSlider = NSSlider(
            value: Double(PopupFontPreferences.load()),
            minValue: Double(PopupFontPreferences.minSize),
            maxValue: Double(PopupFontPreferences.maxSize),
            target: nil,
            action: nil
        )
        popupFontSizeSlider.numberOfTickMarks = Int(PopupFontPreferences.maxSize - PopupFontPreferences.minSize) + 1
        popupFontSizeSlider.allowsTickMarkValuesOnly = true
        popupFontSizeSlider.isContinuous = true
        popupFontSizeValueField = PreferencesWindowController.makeValueField()
        popupFontSizeValueField.alignment = .right
        popupFontSizeValueField.stringValue = PopupFontPreferences.format(PopupFontPreferences.load())

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        stackView.addArrangedSubview(titleField)
        stackView.addArrangedSubview(descriptionField)
        stackView.addArrangedSubview(Self.makeSliderRow(
            labelField: popupFontSizeLabelField,
            slider: popupFontSizeSlider,
            valueField: popupFontSizeValueField
        ))
        stackView.addArrangedSubview(Self.makeRow(labelField: languageLabelField, field: languagePopUp))
        stackView.addArrangedSubview(Self.makeEditRow(label: "OPENAI_API_KEY", field: apiKeyField))
        stackView.addArrangedSubview(Self.makeEditRow(label: "OPENAI_ENDPOINT", field: endpointField))
        stackView.addArrangedSubview(Self.makeEditRow(label: "POPUP_MAX_WIDTH", field: popupMaxWidthField))
        stackView.addArrangedSubview(Self.makeEditRow(label: "POPUP_MAX_HEIGHT", field: popupMaxHeightField))
        stackView.addArrangedSubview(Self.makeEditRow(label: "FORCE_CLICK_PRESSURE_THRESHOLD", field: thresholdField))
        stackView.addArrangedSubview(Self.makeEditRow(label: "FORCE_CLICK_PRESSURE_DELTA", field: deltaField))
        stackView.addArrangedSubview(Self.makeEditRow(label: "FORCE_CLICK_BASELINE_WINDOW_MS", field: windowField))

        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor)
        ])

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 300),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = UIStrings.Preferences.title
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = contentView

        super.init()
        popupFontSizeSlider.target = self
        popupFontSizeSlider.action = #selector(handleFontSizeChange(_:))
        apiKeyField.target = self
        apiKeyField.action = #selector(handleApiKeyChange(_:))
        endpointField.target = self
        endpointField.action = #selector(handleEndpointChange(_:))
        thresholdField.target = self
        thresholdField.action = #selector(handleThresholdChange(_:))
        deltaField.target = self
        deltaField.action = #selector(handleDeltaChange(_:))
        windowField.target = self
        windowField.action = #selector(handleWindowMsChange(_:))
        popupMaxWidthField.target = self
        popupMaxWidthField.action = #selector(handlePopupMaxWidthChange(_:))
        popupMaxHeightField.target = self
        popupMaxHeightField.action = #selector(handlePopupMaxHeightChange(_:))
        languagePopUp.target = self
        languagePopUp.action = #selector(handleLanguageChange(_:))

        apiKeyField.delegate = self
        endpointField.delegate = self
        thresholdField.delegate = self
        deltaField.delegate = self
        windowField.delegate = self
        popupMaxWidthField.delegate = self
        popupMaxHeightField.delegate = self
        refreshValues()
    }

    func show() {
        refreshValues()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(apiKeyField)
    }

    private func refreshValues() {
        apiKeyField.stringValue = AppPreferences.apiKey()
        endpointField.stringValue = AppPreferences.endpoint()
        thresholdField.stringValue = String(format: "%.2f", AppPreferences.pressureThreshold())
        deltaField.stringValue = String(format: "%.2f", AppPreferences.pressureDelta())
        windowField.stringValue = String(format: "%.0f", AppPreferences.baselineWindowMs())
        popupMaxWidthField.stringValue = String(format: "%.0f", AppPreferences.popupMaxWidth())
        popupMaxHeightField.stringValue = String(format: "%.0f", AppPreferences.popupMaxHeight())
        if let index = AppLanguage.allCases.firstIndex(of: AppPreferences.language()) {
            languagePopUp.selectItem(at: index)
        }

        let size = PopupFontPreferences.load()
        popupFontSizeSlider.doubleValue = Double(size)
        popupFontSizeValueField.stringValue = PopupFontPreferences.format(size)
        applyStrings()
    }

    private func applyStrings() {
        titleField.stringValue = UIStrings.Preferences.title
        descriptionField.stringValue = UIStrings.Preferences.description
        popupFontSizeLabelField.stringValue = UIStrings.Preferences.popupFontSizeLabel
        languageLabelField.stringValue = UIStrings.Preferences.languageLabel
        window.title = UIStrings.Preferences.title
    }

    private static func makeValueField() -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        field.textColor = .labelColor
        field.lineBreakMode = .byTruncatingMiddle
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    private static func makeRow(label: String, valueField: NSTextField) -> NSStackView {
        let labelField = NSTextField(labelWithString: label)
        labelField.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        labelField.textColor = .secondaryLabelColor
        labelField.setContentHuggingPriority(.required, for: .horizontal)
        labelField.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView(views: [labelField, valueField])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 12
        return row
    }

    private static func makeRow(labelField: NSTextField, field: NSView) -> NSStackView {
        labelField.setContentHuggingPriority(.required, for: .horizontal)
        labelField.setContentCompressionResistancePriority(.required, for: .horizontal)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [labelField, field])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private static func makeEditRow(label: String, field: NSTextField) -> NSStackView {
        let labelField = NSTextField(labelWithString: label)
        labelField.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        labelField.textColor = .secondaryLabelColor
        labelField.setContentHuggingPriority(.required, for: .horizontal)
        labelField.setContentCompressionResistancePriority(.required, for: .horizontal)

        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [labelField, field])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private static func makeSliderRow(labelField: NSTextField, slider: NSSlider, valueField: NSTextField) -> NSStackView {
        labelField.setContentHuggingPriority(.required, for: .horizontal)
        labelField.setContentCompressionResistancePriority(.required, for: .horizontal)
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        slider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        valueField.setContentHuggingPriority(.required, for: .horizontal)
        valueField.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView(views: [labelField, slider, valueField])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    @objc private func handleFontSizeChange(_ sender: NSSlider) {
        let size = PopupFontPreferences.clamp(CGFloat(sender.doubleValue))
        sender.doubleValue = Double(size)
        popupFontSizeValueField.stringValue = PopupFontPreferences.format(size)
        PopupFontPreferences.save(size)
        onPopupFontSizeChange(size)
    }

    @objc private func handleApiKeyChange(_ sender: NSTextField) {
        AppPreferences.setApiKey(sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @objc private func handleEndpointChange(_ sender: NSTextField) {
        AppPreferences.setEndpoint(sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @objc private func handleThresholdChange(_ sender: NSTextField) {
        if let value = Double(sender.stringValue) {
            AppPreferences.setPressureThreshold(CGFloat(value))
        }
        sender.stringValue = String(format: "%.2f", AppPreferences.pressureThreshold())
        notifyForceClickSettingsChange()
    }

    @objc private func handleDeltaChange(_ sender: NSTextField) {
        if let value = Double(sender.stringValue) {
            AppPreferences.setPressureDelta(CGFloat(value))
        }
        sender.stringValue = String(format: "%.2f", AppPreferences.pressureDelta())
        notifyForceClickSettingsChange()
    }

    @objc private func handleWindowMsChange(_ sender: NSTextField) {
        if let value = Double(sender.stringValue) {
            AppPreferences.setBaselineWindowMs(CGFloat(value))
        }
        sender.stringValue = String(format: "%.0f", AppPreferences.baselineWindowMs())
        notifyForceClickSettingsChange()
    }

    @objc private func handlePopupMaxWidthChange(_ sender: NSTextField) {
        if let value = Double(sender.stringValue) {
            AppPreferences.setPopupMaxWidth(CGFloat(value))
        }
        sender.stringValue = String(format: "%.0f", AppPreferences.popupMaxWidth())
        onPopupLayoutChange()
    }

    @objc private func handlePopupMaxHeightChange(_ sender: NSTextField) {
        if let value = Double(sender.stringValue) {
            AppPreferences.setPopupMaxHeight(CGFloat(value))
        }
        sender.stringValue = String(format: "%.0f", AppPreferences.popupMaxHeight())
        onPopupLayoutChange()
    }

    @objc private func handleLanguageChange(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let language = AppLanguage(rawValue: rawValue) else {
            return
        }
        AppPreferences.setLanguage(language)
        applyStrings()
        onLanguageChange()
    }

    private func notifyForceClickSettingsChange() {
        onForceClickSettingsChange(
            Float(AppPreferences.pressureThreshold()),
            Float(AppPreferences.pressureDelta()),
            TimeInterval(AppPreferences.baselineWindowMs() / 1000)
        )
    }
}

extension PreferencesWindowController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else {
            return
        }
        switch field {
        case apiKeyField:
            handleApiKeyChange(field)
        case endpointField:
            handleEndpointChange(field)
        case popupMaxWidthField:
            handlePopupMaxWidthChange(field)
        case popupMaxHeightField:
            handlePopupMaxHeightChange(field)
        case thresholdField:
            handleThresholdChange(field)
        case deltaField:
            handleDeltaChange(field)
        case windowField:
            handleWindowMsChange(field)
        default:
            break
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else {
            return
        }
        switch field {
        case apiKeyField:
            handleApiKeyChange(field)
        case endpointField:
            handleEndpointChange(field)
        case popupMaxWidthField:
            handlePopupMaxWidthChange(field)
        case popupMaxHeightField:
            handlePopupMaxHeightChange(field)
        case thresholdField:
            handleThresholdChange(field)
        case deltaField:
            handleDeltaChange(field)
        case windowField:
            handleWindowMsChange(field)
        default:
            break
        }
    }
}

@MainActor
private final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let preferencesController: PreferencesWindowController
    private let menu: NSMenu
    private let preferencesItem: NSMenuItem
    private let quitItem: NSMenuItem

    init(preferencesController: PreferencesWindowController) {
        self.preferencesController = preferencesController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu = NSMenu()
        preferencesItem = NSMenuItem(
            title: UIStrings.Menu.preferences,
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        quitItem = NSMenuItem(
            title: UIStrings.Menu.quit,
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        super.init()
        configureStatusItem()
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "text.magnifyingglass", accessibilityDescription: UIStrings.Menu.appTitle)
            image?.isTemplate = true
            button.image = image
            button.toolTip = UIStrings.Menu.appTitle
        }

        preferencesItem.target = self
        menu.addItem(preferencesItem)
        menu.addItem(.separator())

        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func refreshStrings() {
        preferencesItem.title = UIStrings.Menu.preferences
        quitItem.title = UIStrings.Menu.quit
        if let button = statusItem.button {
            button.toolTip = UIStrings.Menu.appTitle
        }
    }

    @objc private func openPreferences() {
        preferencesController.show()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

@MainActor
private let forceClickSelectionPopup = ForceClickSelectionPopup()

private struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var dataByType: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dataByType[type] = data
                }
            }
            return dataByType
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restoredItems = items.map { dataByType -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dataByType {
                item.setData(data, forType: type)
            }
            return item
        }
        if !restoredItems.isEmpty {
            pasteboard.writeObjects(restoredItems)
        }
    }
}

private func findSelectedText(
    in element: AXUIElement,
    maxDepth: Int,
    remainingNodes: inout Int
) -> String? {
    if remainingNodes <= 0 {
        return nil
    }
    remainingNodes -= 1

    if let selectedText = copyAttribute(
        element: element,
        attribute: kAXSelectedTextAttribute as CFString
    ) as? String, !selectedText.isEmpty {
        return selectedText
    }

    if maxDepth == 0 {
        return nil
    }

    guard let children = copyAttribute(
        element: element,
        attribute: kAXChildrenAttribute as CFString
    ) as? [AXUIElement] else {
        return nil
    }

    for child in children {
        if let selectedText = findSelectedText(
            in: child,
            maxDepth: maxDepth - 1,
            remainingNodes: &remainingNodes
        ) {
            return selectedText
        }
    }

    return nil
}

private func copyAttribute(element: AXUIElement, attribute: CFString) -> AnyObject? {
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(element, attribute, &value)
    guard result == .success else {
        return nil
    }
    return value
}

private func copyParameterizedAttribute(
    element: AXUIElement,
    attribute: CFString,
    parameter: AXValue
) -> AnyObject? {
    var value: AnyObject?
    let result = AXUIElementCopyParameterizedAttributeValue(element, attribute, parameter, &value)
    guard result == .success else {
        return nil
    }
    return value
}

private func currentWordRange(in text: String, caretIndex: Int) -> CFRange {
    let cfText = text as CFString
    let length = CFStringGetLength(cfText)
    if length == 0 {
        return CFRange(location: 0, length: 0)
    }

    let clampedIndex = max(0, min(caretIndex, length))
    let locale = Locale.current as CFLocale
    let tokenizer = CFStringTokenizerCreate(
        kCFAllocatorDefault,
        cfText,
        CFRange(location: 0, length: length),
        kCFStringTokenizerUnitWord,
        locale
    )

    CFStringTokenizerGoToTokenAtIndex(tokenizer, clampedIndex)
    var range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
    if range.location == kCFNotFound || range.length == 0, clampedIndex > 0 {
        CFStringTokenizerGoToTokenAtIndex(tokenizer, clampedIndex - 1)
        range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
    }

    if range.location == kCFNotFound || range.length == 0 {
        return CFRange(location: clampedIndex, length: 0)
    }

    return range
}

private final class EventTapController {
    var tap: CFMachPort?
    let monitor: ForceClickMonitor
    private let selectionHandler: ForceClickSelectionHandler
    private static let focusStateLock = OSAllocatedUnfairLock<Bool>(uncheckedState: false)

    init(monitor: ForceClickMonitor, selectionHandler: ForceClickSelectionHandler) {
        self.monitor = monitor
        self.selectionHandler = selectionHandler
    }

    func handle(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        Task { @MainActor in
            EventTapController.refreshFocusState()
        }
        let isPopupOrPreferencesFocused = EventTapController.focusStateLock.withLockUnchecked { $0 }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        switch type {
        case .keyDown:
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            if keyCode == CGKeyCode(kVK_Escape) {
                Task { @MainActor in
                    forceClickSelectionPopup.dismissOnEscape()
                }
            }
        case .leftMouseDown, .rightMouseDown:
            let location = NSEvent.mouseLocation
            Task { @MainActor in
                forceClickSelectionPopup.dismissIfClickOutside(location)
            }
        default:
            break
        }

        switch type {
        case .leftMouseDown:
            selectionHandler.cacheSelectionBeforeMouseDown()
            monitor.setMouseDown(true)
        case .leftMouseUp:
            monitor.setMouseDown(false)
            selectionHandler.clearSelectionCache()
        default:
            break
        }

        if monitor.shouldSuppressEvents(), !isPopupOrPreferencesFocused {
            switch type {
            case .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown:
                return nil
            default:
                break
            }
        }

        return Unmanaged.passRetained(event)
    }

    @MainActor
    private static func refreshFocusState() {
        let isActive = NSApp.isActive
        guard let keyWindow = NSApp.keyWindow else {
            focusStateLock.withLockUnchecked { $0 = false }
            return
        }
        let responder = keyWindow.firstResponder as? NSView
        let isText = responder is NSTextView || responder is NSTextField
        focusStateLock.withLockUnchecked { $0 = isActive && isText }
    }
}

private final class ForceClickEventTap {
    private let controller: EventTapController
    private var runLoopSource: CFRunLoopSource?

    init(monitor: ForceClickMonitor, selectionHandler: ForceClickSelectionHandler) {
        controller = EventTapController(monitor: monitor, selectionHandler: selectionHandler)
    }

    func start() -> Bool {
        let mask = CGEventMask(
            (1 << CGEventType.leftMouseDown.rawValue)
                | (1 << CGEventType.leftMouseUp.rawValue)
                | (1 << CGEventType.leftMouseDragged.rawValue)
                | (1 << CGEventType.rightMouseDown.rawValue)
                | (1 << CGEventType.keyDown.rawValue)
        )

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(controller).toOpaque()
        ) else {
            return false
        }

        controller.tap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passRetained(event)
    }

    let controller = Unmanaged<EventTapController>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    return controller.handle(event: event, type: type)
}

private struct MainMenuReferences {
    let appMenuItem: NSMenuItem
    let quitItem: NSMenuItem
    let editMenuItem: NSMenuItem
    let editMenu: NSMenu
    let undoItem: NSMenuItem
    let redoItem: NSMenuItem
    let cutItem: NSMenuItem
    let copyItem: NSMenuItem
    let pasteItem: NSMenuItem
    let selectAllItem: NSMenuItem
}

@main
struct Digger {
    @MainActor
    private static var mainMenuReferences: MainMenuReferences?

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.mainMenu = buildMainMenu()
        let manager = OMSManager.shared
        let threshold = Float(AppPreferences.pressureThreshold())
        let delta = Float(AppPreferences.pressureDelta())
        let windowMs = Double(AppPreferences.baselineWindowMs())
        let selectionHandler = ForceClickSelectionHandler()
        let monitor = ForceClickMonitor(
            pressureThreshold: threshold,
            pressureDelta: delta,
            baselineWindow: windowMs / 1000,
            onForceClick: {
                selectionHandler.handleForceClick()
            }
        )
        let eventTap = ForceClickEventTap(monitor: monitor, selectionHandler: selectionHandler)
        weak var menuBarController: MenuBarController?
        let preferencesController = PreferencesWindowController(
            onPopupFontSizeChange: { newSize in
                forceClickSelectionPopup.applyPopupTextSize(newSize)
            },
            onPopupLayoutChange: {
                forceClickSelectionPopup.refreshLayout()
            },
            onLanguageChange: {
                forceClickSelectionPopup.applyStrings()
                forceClickSelectionPopup.refreshLayout()
                menuBarController?.refreshStrings()
                applyMainMenuStrings()
            },
            onForceClickSettingsChange: { newThreshold, newDelta, newWindow in
                monitor.updateSettings(
                    pressureThreshold: newThreshold,
                    pressureDelta: newDelta,
                    baselineWindow: newWindow
                )
            }
        )
        let menuController = MenuBarController(preferencesController: preferencesController)
        menuBarController = menuController

        Task {
            for await touches in manager.touchDataStream {
                monitor.update(touches: touches)
            }
        }

        if !manager.startListening() {
            print("Failed to start OpenMultitouchSupport listener.")
        }

        if !eventTap.start() {
            print("Failed to register event tap. Enable Accessibility permissions.")
        } else {
            print("Force click monitor started.")
        }

        withExtendedLifetime(menuController) {
            withExtendedLifetime(eventTap) {
                app.run()
            }
        }
    }

    @MainActor
    private static func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem(title: UIStrings.Menu.appTitle, action: nil, keyEquivalent: "")
        let appMenu = NSMenu()
        let quitItem = NSMenuItem(
            title: UIStrings.Menu.quit,
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem(title: UIStrings.Menu.edit, action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: UIStrings.Menu.edit)
        let undoItem = NSMenuItem(title: UIStrings.Menu.undo, action: #selector(UndoManager.undo), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: UIStrings.Menu.redo, action: #selector(UndoManager.redo), keyEquivalent: "Z")
        editMenu.addItem(undoItem)
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
        let cutItem = NSMenuItem(title: UIStrings.Menu.cut, action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        let copyItem = NSMenuItem(title: UIStrings.Menu.copy, action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        let pasteItem = NSMenuItem(title: UIStrings.Menu.paste, action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let selectAllItem = NSMenuItem(title: UIStrings.Menu.selectAll, action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(cutItem)
        editMenu.addItem(copyItem)
        editMenu.addItem(pasteItem)
        editMenu.addItem(selectAllItem)
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        mainMenuReferences = MainMenuReferences(
            appMenuItem: appMenuItem,
            quitItem: quitItem,
            editMenuItem: editMenuItem,
            editMenu: editMenu,
            undoItem: undoItem,
            redoItem: redoItem,
            cutItem: cutItem,
            copyItem: copyItem,
            pasteItem: pasteItem,
            selectAllItem: selectAllItem
        )

        return mainMenu
    }

    @MainActor
    private static func applyMainMenuStrings() {
        guard let refs = mainMenuReferences else {
            return
        }
        refs.appMenuItem.title = UIStrings.Menu.appTitle
        refs.quitItem.title = UIStrings.Menu.quit
        refs.editMenuItem.title = UIStrings.Menu.edit
        refs.editMenu.title = UIStrings.Menu.edit
        refs.undoItem.title = UIStrings.Menu.undo
        refs.redoItem.title = UIStrings.Menu.redo
        refs.cutItem.title = UIStrings.Menu.cut
        refs.copyItem.title = UIStrings.Menu.copy
        refs.pasteItem.title = UIStrings.Menu.paste
        refs.selectAllItem.title = UIStrings.Menu.selectAll
    }
}
