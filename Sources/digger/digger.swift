import ApplicationServices
import AppKit
import Carbon
import Foundation
import OpenMultitouchSupport
import OpenAI
import os

private final class ForceClickMonitor {
    private let pressureThreshold: Float
    private let pressureDelta: Float
    private let baselineWindow: TimeInterval
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
        self.pressureThreshold = pressureThreshold
        self.pressureDelta = pressureDelta
        self.baselineWindow = baselineWindow
        self.onForceClick = onForceClick
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

    init?(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard let token = environment["OPENAI_API_KEY"], !token.isEmpty else {
            return nil
        }

        var host = "api.openai.com"
        var basePath = "/v1"
        var port = 443
        var scheme = "https"
        if let endpointText = environment["OPENAI_ENDPOINT"],
           !endpointText.isEmpty,
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
    private let translator = OpenAITranslator()

    func handleForceClick() {
        guard let text = fetchOrSelectText(), !text.isEmpty else {
            if let fallbackText = copySelectionText(selectWordIfNeeded: true), !fallbackText.isEmpty {
                print(fallbackText)
                translateAndShow(text: fallbackText)
            }
            return
        }
        print(text)
        translateAndShow(text: text)
    }

    private func translateAndShow(text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }
        guard let location = currentMouseLocation() else {
            return
        }
        let translator = self.translator
        let requestID = UUID()
        Task { @MainActor in
            forceClickSelectionPopup.showLoading(original: trimmedText, near: location, requestID: requestID)
        }
        Task { [trimmedText, location, requestID] in
            let translation: String
            if let translator {
                do {
                    let result = try await translator.translate(trimmedText)
                    translation = result.isEmpty ? "翻译结果为空" : result
                } catch {
                    translation = "翻译失败"
                }
            } else {
                translation = "未检测到 OPENAI_API_KEY"
            }
            print("译文: \(translation)")
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
        if let axRange {
            let status = AXUIElementSetAttributeValue(
                focusedElement,
                kAXSelectedTextRangeAttribute as CFString,
                axRange
            )
            if status != AXError.success {
                return nil
            }
        }

        if let selectedText = copyAttribute(
            element: focusedElement,
            attribute: kAXSelectedTextAttribute as CFString
        ) as? String, !selectedText.isEmpty {
            return selectedText
        }

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
        Thread.sleep(forTimeInterval: 0.08)
        var copiedText = pasteboard.string(forType: .string)
        let didChange = pasteboard.changeCount != changeCount
        if !didChange || copiedText?.isEmpty ?? true {
            copiedText = nil
        }

        if copiedText == nil, selectWordIfNeeded {
            if let location = currentEventTapMouseLocation() ?? currentMouseLocation() {
                performDoubleClick(at: location)
                Thread.sleep(forTimeInterval: 0.06)
                let retryChangeCount = pasteboard.changeCount
                sendCopyCommand()
                Thread.sleep(forTimeInterval: 0.08)
                let retryText = pasteboard.string(forType: .string)
                let retryDidChange = pasteboard.changeCount != retryChangeCount
                if retryDidChange, !(retryText?.isEmpty ?? true) {
                    copiedText = retryText
                }
            }
        }

        snapshot.restore(to: pasteboard)
        return copiedText
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

private final class DraggableContentView: NSView {
    override var mouseDownCanMoveWindow: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        self
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
    private var loadingTimer: Timer?
    private var loadingDotCount = 0
    private var currentRequestID: UUID?

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        originalTitleField = NSTextField(labelWithString: "原文")
        originalTitleField.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        originalTitleField.textColor = .secondaryLabelColor
        originalTitleField.backgroundColor = .clear
        originalTitleField.isEditable = false
        originalTitleField.isSelectable = false

        originalTextField = NSTextField(labelWithString: "")
        originalTextField.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        originalTextField.textColor = .labelColor
        originalTextField.backgroundColor = .clear
        originalTextField.isEditable = false
        originalTextField.isSelectable = false
        originalTextField.lineBreakMode = .byWordWrapping
        originalTextField.maximumNumberOfLines = 6
        originalTextField.cell?.wraps = true
        originalTextField.cell?.usesSingleLineMode = false

        translationTitleField = NSTextField(labelWithString: "译文")
        translationTitleField.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        translationTitleField.textColor = .secondaryLabelColor
        translationTitleField.backgroundColor = .clear
        translationTitleField.isEditable = false
        translationTitleField.isSelectable = false

        translationTextField = NSTextField(labelWithString: "")
        translationTextField.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        translationTextField.textColor = .labelColor
        translationTextField.backgroundColor = .clear
        translationTextField.isEditable = false
        translationTextField.isSelectable = false
        translationTextField.lineBreakMode = .byWordWrapping
        translationTextField.maximumNumberOfLines = 6
        translationTextField.cell?.wraps = true
        translationTextField.cell?.usesSingleLineMode = false

        loadingTextField = NSTextField(labelWithString: "")
        loadingTextField.font = NSFont.systemFont(ofSize: 11, weight: .regular)
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
        contentView.addSubview(originalTitleField)
        contentView.addSubview(originalTextField)
        contentView.addSubview(dividerView)
        contentView.addSubview(translationTitleField)
        contentView.addSubview(translationTextField)
        contentView.addSubview(loadingTextField)

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
    }

    func showLoading(original: String, near location: CGPoint, requestID: UUID) {
        let trimmedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOriginal.isEmpty else {
            return
        }

        currentRequestID = requestID
        originalTextField.stringValue = trimmedOriginal
        translationTextField.stringValue = ""
        startLoadingAnimation()
        let contentSize = layoutContent(showTranslation: false, showLoading: true)
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
        translationTextField.stringValue = trimmedTranslation
        let contentSize = layoutContent(showTranslation: true, showLoading: false)
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
        originalTextField.stringValue = trimmedOriginal
        translationTextField.stringValue = trimmedTranslation
        let contentSize = layoutContent(showTranslation: true, showLoading: false)
        setWindowFrame(contentSize: contentSize, near: location, animated: false)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func layoutContent(showTranslation: Bool, showLoading: Bool) -> CGSize {
        dividerView.isHidden = !showTranslation
        translationTitleField.isHidden = !showTranslation
        translationTextField.isHidden = !showTranslation
        loadingTextField.isHidden = !showLoading

        let padding = CGSize(width: 10, height: 8)
        let maxWidth: CGFloat = 320
        let titleTextSpacing: CGFloat = 2
        let dividerHeight: CGFloat = 1
        let dividerSpacing: CGFloat = 6
        let loadingSpacing: CGFloat = 6

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
        let originalTitleSize = (originalTitleField.stringValue as NSString).size(withAttributes: titleAttributes)
        let translationTitleSize = (translationTitleField.stringValue as NSString).size(withAttributes: titleAttributes)
        let textMaxWidth = maxWidth - padding.width * 2
        let originalTextSize = textSize(for: originalTextField, maxWidth: textMaxWidth)
        let translationTextSize = textSize(for: translationTextField, maxWidth: textMaxWidth)
        let loadingTextSize = textSize(for: loadingTextField, maxWidth: textMaxWidth)

        let contentTextWidth = max(
            originalTitleSize.width,
            originalTextSize.width,
            showTranslation ? max(translationTitleSize.width, translationTextSize.width) : 0,
            showLoading ? loadingTextSize.width : 0
        )
        let contentWidth = min(maxWidth, max(contentTextWidth + padding.width * 2, 120))

        let originalTitleHeight = ceil(originalTitleSize.height)
        let translationTitleHeight = ceil(translationTitleSize.height)
        let originalTextHeight = max(ceil(originalTextSize.height), 16)
        let translationTextHeight = max(ceil(translationTextSize.height), 16)
        let loadingTextHeight = max(ceil(loadingTextSize.height), 14)
        let contentHeight = padding.height * 2 + 4
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

        let titleX = padding.width
        let textX = padding.width
        let availableWidth = contentWidth - padding.width * 2
        originalTextField.preferredMaxLayoutWidth = availableWidth
        translationTextField.preferredMaxLayoutWidth = availableWidth

        var y = contentHeight - padding.height - originalTitleHeight

        originalTitleField.frame = NSRect(
            x: titleX,
            y: y,
            width: availableWidth,
            height: originalTitleHeight
        )
        y -= titleTextSpacing + originalTextHeight

        originalTextField.frame = NSRect(
            x: textX,
            y: y,
            width: availableWidth,
            height: originalTextHeight
        )
        if showLoading {
            y -= loadingSpacing + loadingTextHeight
            loadingTextField.frame = NSRect(
                x: textX,
                y: y,
                width: availableWidth,
                height: loadingTextHeight
            )
        }

        if showTranslation {
            y -= dividerSpacing + dividerHeight

            dividerView.frame = NSRect(
                x: padding.width,
                y: y,
                width: availableWidth,
                height: dividerHeight
            )
            y -= dividerSpacing + translationTitleHeight

            translationTitleField.frame = NSRect(
                x: titleX,
                y: y,
                width: availableWidth,
                height: translationTitleHeight
            )
            y -= titleTextSpacing + translationTextHeight

            translationTextField.frame = NSRect(
                x: textX,
                y: y,
                width: availableWidth,
                height: translationTextHeight
            )
        }

        let contentSize = CGSize(width: contentWidth, height: contentHeight)
        contentView.frame = NSRect(origin: .zero, size: contentSize)
        return contentSize
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
        loadingTextField.stringValue = "译文翻译中" + dots
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

@MainActor
private final class PreferencesWindowController {
    private let window: NSWindow
    private let apiKeyValueField: NSTextField
    private let endpointValueField: NSTextField
    private let thresholdValueField: NSTextField
    private let deltaValueField: NSTextField
    private let windowValueField: NSTextField

    init() {
        let contentView = NSView()
        contentView.wantsLayer = true

        let titleField = NSTextField(labelWithString: "Preferences")
        titleField.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        titleField.textColor = .labelColor

        let descriptionField = NSTextField(wrappingLabelWithString: "配置通过环境变量设置，修改后请重启 Digger。")
        descriptionField.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        descriptionField.textColor = .secondaryLabelColor

        apiKeyValueField = PreferencesWindowController.makeValueField()
        endpointValueField = PreferencesWindowController.makeValueField()
        thresholdValueField = PreferencesWindowController.makeValueField()
        deltaValueField = PreferencesWindowController.makeValueField()
        windowValueField = PreferencesWindowController.makeValueField()

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        stackView.addArrangedSubview(titleField)
        stackView.addArrangedSubview(descriptionField)
        stackView.addArrangedSubview(Self.makeRow(label: "OPENAI_API_KEY", valueField: apiKeyValueField))
        stackView.addArrangedSubview(Self.makeRow(label: "OPENAI_ENDPOINT", valueField: endpointValueField))
        stackView.addArrangedSubview(Self.makeRow(label: "FORCE_CLICK_PRESSURE_THRESHOLD", valueField: thresholdValueField))
        stackView.addArrangedSubview(Self.makeRow(label: "FORCE_CLICK_PRESSURE_DELTA", valueField: deltaValueField))
        stackView.addArrangedSubview(Self.makeRow(label: "FORCE_CLICK_BASELINE_WINDOW_MS", valueField: windowValueField))

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
        window.title = "Preferences"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = contentView

        refreshValues()
    }

    func show() {
        refreshValues()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshValues() {
        let env = ProcessInfo.processInfo.environment
        let apiKey = env["OPENAI_API_KEY"] ?? ""
        if apiKey.isEmpty {
            apiKeyValueField.stringValue = "未设置"
        } else if apiKey.count <= 8 {
            apiKeyValueField.stringValue = "已设置 (\(apiKey))"
        } else {
            apiKeyValueField.stringValue = "已设置 (…\(apiKey.suffix(4)))"
        }

        let endpoint = env["OPENAI_ENDPOINT"] ?? ""
        endpointValueField.stringValue = endpoint.isEmpty ? "默认 (https://api.openai.com/v1)" : endpoint

        thresholdValueField.stringValue = valueFromEnv(
            env["FORCE_CLICK_PRESSURE_THRESHOLD"],
            defaultValue: "3.0"
        )
        deltaValueField.stringValue = valueFromEnv(
            env["FORCE_CLICK_PRESSURE_DELTA"],
            defaultValue: "2.0"
        )
        windowValueField.stringValue = valueFromEnv(
            env["FORCE_CLICK_BASELINE_WINDOW_MS"],
            defaultValue: "120 ms"
        )
    }

    private func valueFromEnv(_ value: String?, defaultValue: String) -> String {
        guard let value, !value.isEmpty else {
            return "\(defaultValue) (默认)"
        }
        return value
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
}

@MainActor
private final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let preferencesController: PreferencesWindowController

    init(preferencesController: PreferencesWindowController) {
        self.preferencesController = preferencesController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureStatusItem()
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "text.magnifyingglass", accessibilityDescription: "Digger")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Digger"
        }

        let menu = NSMenu()
        let preferencesItem = NSMenuItem(
            title: "Preferences…",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        preferencesItem.target = self
        menu.addItem(preferencesItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Digger",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
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

    init(monitor: ForceClickMonitor) {
        self.monitor = monitor
    }

    func handle(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
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
            monitor.setMouseDown(true)
        case .leftMouseUp:
            monitor.setMouseDown(false)
        default:
            break
        }

        if monitor.shouldSuppressEvents() {
            return nil
        }

        return Unmanaged.passRetained(event)
    }
}

private final class ForceClickEventTap {
    private let controller: EventTapController
    private var runLoopSource: CFRunLoopSource?

    init(monitor: ForceClickMonitor) {
        controller = EventTapController(monitor: monitor)
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

@main
struct Digger {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let preferencesController = PreferencesWindowController()
        let menuBarController = MenuBarController(preferencesController: preferencesController)

        let manager = OMSManager.shared
        let thresholdText = ProcessInfo.processInfo.environment["FORCE_CLICK_PRESSURE_THRESHOLD"]
        let deltaText = ProcessInfo.processInfo.environment["FORCE_CLICK_PRESSURE_DELTA"]
        let windowText = ProcessInfo.processInfo.environment["FORCE_CLICK_BASELINE_WINDOW_MS"]
        let threshold = Float(thresholdText ?? "") ?? 3.0
        let delta = Float(deltaText ?? "") ?? 2.0
        let windowMs = Double(windowText ?? "") ?? 120
        let selectionHandler = ForceClickSelectionHandler()
        let monitor = ForceClickMonitor(
            pressureThreshold: threshold,
            pressureDelta: delta,
            baselineWindow: windowMs / 1000,
            onForceClick: {
                selectionHandler.handleForceClick()
            }
        )
        let eventTap = ForceClickEventTap(monitor: monitor)

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

        withExtendedLifetime(menuBarController) {
            withExtendedLifetime(eventTap) {
                app.run()
            }
        }
    }
}
