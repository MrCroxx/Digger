import AppKit
import Carbon
import Foundation
import QuartzCore

final class DraggableContentView: NSView {
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

final class DraggableScrollView: NSScrollView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let contentView = documentView {
            let contentPoint = contentView.convert(point, from: self)
            let hitView = contentView.hitTest(contentPoint)
            if findSelectableTextView(from: hitView) != nil {
                super.mouseDown(with: event)
                return
            }
        }
        window?.performDrag(with: event)
    }

    private func findSelectableTextView(from view: NSView?) -> NSView? {
        var current = view
        while let currentView = current {
            if let textField = currentView as? NSTextField, textField.isSelectable {
                return textField
            }
            if let textView = currentView as? NSTextView, textView.isSelectable {
                return textView
            }
            current = currentView.superview
        }
        return nil
    }
}

final class PopupResultTextView: NSTextView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

final class HoverableIconButton: NSButton {
    var onHover: ((Bool) -> Void)?
    var tooltipText: String = ""
    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = hoverTrackingArea {
            removeTrackingArea(existing)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover?(false)
    }
}

final class HoverTooltipWindow: NSWindow {
    private let label: NSTextField
    private let padding = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
    private let maxTextWidth: CGFloat = 220

    init() {
        label = NSTextField(wrappingLabelWithString: "")
        label.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        label.textColor = .labelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.cell?.wraps = true
        label.cell?.usesSingleLineMode = false
        let contentView = NSView()
        contentView.addSubview(label)
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 24),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .transient]
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 6
        contentView.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.95).cgColor
        self.contentView = contentView
    }

    override var canBecomeKey: Bool {
        false
    }

    func show(text: String, near anchor: NSRect, fontSize: CGFloat) {
        let size = prepareLayout(text: text, fontSize: fontSize)
        let x = anchor.midX - size.width * 0.5
        let y = anchor.minY - size.height - 6
        setFrameOrigin(NSPoint(x: x, y: y))
        orderFront(nil)
    }

    func showCentered(text: String, in frame: NSRect, fontSize: CGFloat) {
        let size = prepareLayout(text: text, fontSize: fontSize)
        let x = frame.midX - size.width * 0.5
        let y = frame.midY - size.height * 0.5
        setFrameOrigin(NSPoint(x: x, y: y))
        orderFront(nil)
    }

    private func prepareLayout(text: String, fontSize: CGFloat) -> CGSize {
        label.font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        label.stringValue = text
        let font = label.font ?? NSFont.systemFont(ofSize: 11, weight: .regular)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let maxSize = CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude)
        let boundingRect = attributed.boundingRect(
            with: maxSize,
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let textWidth = ceil(boundingRect.width) + 4
        let textHeight = ceil(boundingRect.height) + 2
        let contentWidth = min(maxTextWidth, textWidth)
        let width = contentWidth + padding.left + padding.right
        let height = textHeight + padding.top + padding.bottom
        label.preferredMaxLayoutWidth = contentWidth
        label.frame = NSRect(
            x: padding.left,
            y: padding.bottom,
            width: contentWidth,
            height: textHeight
        )
        setContentSize(NSSize(width: width, height: height))
        return CGSize(width: width, height: height)
    }

    func hide() {
        orderOut(nil)
    }
}

@MainActor
final class ForceClickSelectionPopup {
    private struct TextMeasurementCacheEntry {
        let revision: UInt64
        let maxWidth: CGFloat
        let fontPointSize: CGFloat
        let size: CGSize
    }

    private let window: PopupWindow
    private let originalTitleField: NSTextField
    private let originalTextField: NSTextField
    private let originalCollapseButton: HoverableIconButton
    private let contentView: DraggableContentView
    private let headerView: NSView
    private let modelLabelField: NSTextField
    private let headerDividerView: NSView
    private let scrollView: DraggableScrollView
    private let documentView: NSView
    private let originalCopyButton: HoverableIconButton
    private let retryButton: HoverableIconButton
    private let copyAllButton: HoverableIconButton
    private let preferencesButton: HoverableIconButton
    private let actionButtons: [HoverableIconButton]
    private let tooltipWindow: HoverTooltipWindow
    private var tooltipTimer: Timer?
    private var copyFeedbackTimer: Timer?
    private weak var hoveredButton: HoverableIconButton?
    var onOpenPreferences: (() -> Void)?
    var onRetry: ((String, CGPoint) -> Void)?
    private var loadingTimer: Timer?
    private var loadingDotCount = 0
    private var currentRequestID: UUID?
    private var lastAnchorLocation: CGPoint?
    private let baseTitleSize: CGFloat = 11
    private let baseTextSize: CGFloat = 12
    private let baseTooltipSize: CGFloat = 11
    private var functionSections: [FunctionSection] = []
    private var functionIDs: [UUID] = []
    private var originalIsCollapsed = false
    private var layoutUpdateTimer: Timer?
    private var pendingLayoutLocation: CGPoint?
    private var pendingLayoutAnimate = false
    private var lastWindowFrame: NSRect?
    private let layoutDebounceInterval: TimeInterval = 0.08
    private let streamingLayoutDebounceInterval: TimeInterval = 0.12
    private let streamingFadeInterval: TimeInterval = 0.08
    private let streamingFadeDuration: CFTimeInterval = 0.08
    private var streamFadeTimestamps: [UUID: TimeInterval] = [:]
    private var textMeasurementCache: [ObjectIdentifier: TextMeasurementCacheEntry] = [:]
    private var nextTextRevision: UInt64 = 1
    private var originalTextRevision: UInt64 = 0

    private struct FunctionSection {
        let function: PopupFunction
        let titleField: NSTextField
        let textView: PopupResultTextView
        let cacheHitButton: HoverableIconButton
        let collapseButton: HoverableIconButton
        let copyButton: HoverableIconButton
        let dividerView: NSView
        var isLoading: Bool
        var isCollapsed: Bool
        var isCacheHit: Bool
        var textRevision: UInt64
    }

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
        originalTextField.isSelectable = true
        originalTextField.lineBreakMode = .byWordWrapping
        originalTextField.maximumNumberOfLines = 0
        originalTextField.cell?.wraps = true
        originalTextField.cell?.usesSingleLineMode = false
        originalTextField.wantsLayer = true

        originalCopyButton = ForceClickSelectionPopup.makeIconButton(
            symbolName: "doc.on.doc",
            toolTip: UIStrings.Popup.copyResult,
            target: nil,
            action: #selector(handleCopyOriginal)
        )

        originalCollapseButton = ForceClickSelectionPopup.makeIconButton(
            symbolName: "chevron.down",
            toolTip: UIStrings.Popup.collapseResult,
            target: nil,
            action: #selector(handleToggleOriginalCollapse)
        )

        copyAllButton = ForceClickSelectionPopup.makeIconButton(
            symbolName: "doc.on.doc",
            toolTip: UIStrings.Popup.copyAll,
            target: nil,
            action: #selector(handleCopyAll)
        )
        retryButton = ForceClickSelectionPopup.makeIconButton(
            symbolName: "arrow.clockwise",
            toolTip: UIStrings.Popup.retry,
            target: nil,
            action: #selector(handleRetry)
        )
        preferencesButton = ForceClickSelectionPopup.makeIconButton(
            symbolName: "gearshape",
            toolTip: UIStrings.Popup.openPreferences,
            target: nil,
            action: #selector(handleOpenPreferences)
        )
        actionButtons = [retryButton, copyAllButton, preferencesButton]
        tooltipWindow = HoverTooltipWindow()

        contentView = DraggableContentView()
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 8
        headerView = NSView()
        modelLabelField = NSTextField(labelWithString: "")
        modelLabelField.font = NSFont.systemFont(ofSize: baseTitleSize, weight: .semibold)
        modelLabelField.textColor = .secondaryLabelColor
        modelLabelField.backgroundColor = .clear
        modelLabelField.isEditable = false
        modelLabelField.isSelectable = false
        modelLabelField.lineBreakMode = .byTruncatingTail
        headerDividerView = NSView()
        headerDividerView.wantsLayer = true
        headerDividerView.layer?.backgroundColor = NSColor.separatorColor.cgColor
        documentView = NSView()
        documentView.addSubview(originalTitleField)
        documentView.addSubview(originalTextField)
        documentView.addSubview(originalCollapseButton)
        documentView.addSubview(originalCopyButton)

        scrollView = DraggableScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.documentView = documentView
        headerView.addSubview(modelLabelField)
        headerView.addSubview(retryButton)
        headerView.addSubview(copyAllButton)
        headerView.addSubview(preferencesButton)
        contentView.addSubview(scrollView)
        contentView.addSubview(headerView)
        contentView.addSubview(headerDividerView)

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
        window.onDismiss = { [weak self] in
            self?.dismissPopup()
        }
        window.onCopyShortcut = { [weak self] includeOriginal in
            self?.handleCopyShortcut(includeOriginal: includeOriginal) ?? false
        }

        for button in actionButtons {
            button.target = self
            button.onHover = { [weak self, weak button] isHovering in
                guard let self, let button else {
                    return
                }
                self.handleHover(isHovering, for: button)
            }
        }
        originalCopyButton.target = self
        originalCopyButton.onHover = { [weak self] isHovering in
            guard let self else {
                return
            }
            self.handleHover(isHovering, for: self.originalCopyButton)
        }
        originalCollapseButton.target = self
        originalCollapseButton.onHover = { [weak self] isHovering in
            guard let self else {
                return
            }
            self.handleHover(isHovering, for: self.originalCollapseButton)
        }

        applyPopupTextSize(PopupFontPreferences.load())
        applyPopupOpacity(AppPreferences.popupOpacity())
        applyStrings()
        updateActionButtons()
    }

    func showLoading(original: String, near location: CGPoint, requestID: UUID, functions: [PopupFunction]) {
        let trimmedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOriginal.isEmpty else {
            return
        }

        currentRequestID = requestID
        lastAnchorLocation = location
        cancelPendingLayoutUpdate()
        originalTextField.stringValue = trimmedOriginal
        originalTextRevision = takeNextTextRevision()
        originalIsCollapsed = AppPreferences.popupOriginalCollapsed()
        originalTextField.isHidden = originalIsCollapsed
        updateOriginalCollapseButton()
        configureFunctionSections(functions)
        for index in functionSections.indices {
            functionSections[index].isLoading = true
            functionSections[index].isCacheHit = false
        }
        startLoadingAnimation()
        updateActionButtons()
        let contentSize = layoutContent(near: location)
        setWindowFrame(contentSize: contentSize, near: location, animated: false)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func updateResult(
        _ result: String,
        for requestID: UUID,
        functionID: UUID,
        near location: CGPoint,
        isFinal: Bool,
        isCacheHit: Bool
    ) {
        guard currentRequestID == requestID else {
            return
        }
        let updatedResult = isFinal
            ? result.trimmingCharacters(in: .whitespacesAndNewlines)
            : result
        lastAnchorLocation = location
        let didUpdate = updateFunctionSection(
            functionID: functionID,
            text: updatedResult,
            isFinal: isFinal,
            isCacheHit: isCacheHit
        )
        guard didUpdate else {
            return
        }
        updateActionButtons()
        let shouldAnimate = isFinal && !isCacheHit && !functionSections.contains(where: { $0.isLoading })
        scheduleLayoutUpdate(near: location, animated: shouldAnimate, streaming: !isFinal)
    }

    func markStreamingStarted(for requestID: UUID, functionID: UUID, near location: CGPoint) {
        guard currentRequestID == requestID,
              let index = functionSections.firstIndex(where: { $0.function.id == functionID }) else {
            return
        }
        let previousLoading = functionSections[index].isLoading
        let previousText = functionSections[index].textView.string
        functionSections[index].isLoading = false
        if !previousText.isEmpty {
            replaceResultText(in: functionSections[index].textView, with: "")
            functionSections[index].textRevision = takeNextTextRevision()
        }
        guard previousLoading || !previousText.isEmpty else {
            return
        }
        if !functionSections.contains(where: { $0.isLoading }) {
            stopLoadingAnimation()
        }
        updateActionButtons()
        scheduleLayoutUpdate(near: location, animated: false, streaming: true)
    }

    func applyPopupTextSize(_ textSize: CGFloat) {
        let clampedSize = PopupFontPreferences.clamp(textSize)
        let scale = clampedSize / baseTextSize
        originalTitleField.font = NSFont.systemFont(ofSize: baseTitleSize * scale, weight: .semibold)
        originalTextField.font = NSFont.systemFont(ofSize: baseTextSize * scale, weight: .medium)
        modelLabelField.font = NSFont.systemFont(ofSize: baseTitleSize * scale, weight: .semibold)
        for index in functionSections.indices {
            functionSections[index].titleField.font = NSFont.systemFont(ofSize: baseTitleSize * scale, weight: .semibold)
            let font = NSFont.systemFont(ofSize: baseTextSize * scale, weight: .medium)
            applyResultTextViewStyle(functionSections[index].textView, font: font)
        }
        textMeasurementCache.removeAll()

        if window.isVisible, let location = lastAnchorLocation {
            let contentSize = layoutContent(near: location)
            setWindowFrame(contentSize: contentSize, near: location, animated: false)
        }
    }

    func applyPopupOpacity(_ opacity: CGFloat) {
        let clampedOpacity = min(max(opacity, 0), 100)
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor
            .withAlphaComponent(clampedOpacity / 100)
            .cgColor
    }

    func applyStrings() {
        originalTitleField.stringValue = UIStrings.Popup.originalTitle
        originalCopyButton.tooltipText = UIStrings.Popup.copyResult
        updateOriginalCollapseButton()
        for index in functionSections.indices {
            functionSections[index].copyButton.tooltipText = UIStrings.Popup.copyResult
            functionSections[index].cacheHitButton.tooltipText = UIStrings.Popup.cacheHit
            updateCollapseButton(for: index)
        }
        retryButton.tooltipText = UIStrings.Popup.retry
        copyAllButton.tooltipText = UIStrings.Popup.copyAll
        preferencesButton.tooltipText = UIStrings.Popup.openPreferences
        updateLoadingText()
    }

    func refreshLayout() {
        guard window.isVisible, let location = lastAnchorLocation else {
            return
        }
        cancelPendingLayoutUpdate()
        let contentSize = layoutContent(near: location)
        setWindowFrame(contentSize: contentSize, near: location, animated: false)
    }

    private func configureFunctionSections(_ functions: [PopupFunction]) {
        let ids = functions.map { $0.id }
        let scale = PopupFontPreferences.load() / baseTextSize
        let collapsedIDs = AppPreferences.popupCollapsedFunctionIDs()
        let needsRebuild = ids != functionIDs
        if needsRebuild {
            textMeasurementCache.removeAll()
            for section in functionSections {
                section.titleField.removeFromSuperview()
                section.textView.removeFromSuperview()
                section.cacheHitButton.removeFromSuperview()
                section.collapseButton.removeFromSuperview()
                section.copyButton.removeFromSuperview()
                section.dividerView.removeFromSuperview()
            }
            functionSections.removeAll()
            functionIDs = ids
            for function in functions {
                let isCollapsed = collapsedIDs.contains(function.id)
                let titleField = NSTextField(labelWithString: function.title)
                titleField.font = NSFont.systemFont(ofSize: baseTitleSize * scale, weight: .semibold)
                titleField.textColor = .secondaryLabelColor
                titleField.backgroundColor = .clear
                titleField.isEditable = false
                titleField.isSelectable = false

                let textContainer = NSTextContainer(
                    size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
                )
                textContainer.lineFragmentPadding = 0
                textContainer.widthTracksTextView = true
                textContainer.heightTracksTextView = false
                let layoutManager = NSLayoutManager()
                layoutManager.addTextContainer(textContainer)
                let textStorage = NSTextStorage()
                textStorage.addLayoutManager(layoutManager)
                let textView = PopupResultTextView(frame: .zero, textContainer: textContainer)
                textView.drawsBackground = false
                textView.isEditable = false
                textView.isSelectable = true
                textView.isRichText = false
                textView.importsGraphics = false
                textView.textContainerInset = NSSize(width: 0, height: 0)
                textView.isHorizontallyResizable = false
                textView.isVerticallyResizable = false
                textView.maxSize = CGSize(
                    width: CGFloat.greatestFiniteMagnitude,
                    height: CGFloat.greatestFiniteMagnitude
                )
                textView.minSize = NSSize(width: 0, height: 0)
                textView.string = ""
                textView.isHidden = isCollapsed
                textView.wantsLayer = true
                let textFont = NSFont.systemFont(ofSize: baseTextSize * scale, weight: .medium)
                applyResultTextViewStyle(textView, font: textFont)

                let collapseButton = ForceClickSelectionPopup.makeIconButton(
                    symbolName: isCollapsed ? "chevron.right" : "chevron.down",
                    toolTip: isCollapsed ? UIStrings.Popup.expandResult : UIStrings.Popup.collapseResult,
                    target: self,
                    action: #selector(handleToggleSectionCollapse(_:))
                )
                collapseButton.onHover = { [weak self, weak collapseButton] isHovering in
                    guard let self, let collapseButton else {
                        return
                    }
                    self.handleHover(isHovering, for: collapseButton)
                }

                let cacheHitButton = ForceClickSelectionPopup.makeIconButton(
                    symbolName: "internaldrive.fill",
                    toolTip: UIStrings.Popup.cacheHit,
                    target: self,
                    action: #selector(handleSectionCacheHitIndicator(_:))
                )
                cacheHitButton.isHidden = true
                cacheHitButton.onHover = { [weak self, weak cacheHitButton] isHovering in
                    guard let self, let cacheHitButton else {
                        return
                    }
                    self.handleHover(isHovering, for: cacheHitButton)
                }

                let copyButton = ForceClickSelectionPopup.makeIconButton(
                    symbolName: "doc.on.doc",
                    toolTip: UIStrings.Popup.copyResult,
                    target: self,
                    action: #selector(handleCopySection(_:))
                )
                copyButton.onHover = { [weak self, weak copyButton] isHovering in
                    guard let self, let copyButton else {
                        return
                    }
                    self.handleHover(isHovering, for: copyButton)
                }

                let dividerView = NSView()
                dividerView.wantsLayer = true
                dividerView.layer?.backgroundColor = NSColor.separatorColor.cgColor

                documentView.addSubview(dividerView)
                documentView.addSubview(titleField)
                documentView.addSubview(textView)
                documentView.addSubview(cacheHitButton)
                documentView.addSubview(collapseButton)
                documentView.addSubview(copyButton)

                functionSections.append(FunctionSection(
                    function: function,
                    titleField: titleField,
                    textView: textView,
                    cacheHitButton: cacheHitButton,
                    collapseButton: collapseButton,
                    copyButton: copyButton,
                    dividerView: dividerView,
                    isLoading: true,
                    isCollapsed: isCollapsed,
                    isCacheHit: false,
                    textRevision: takeNextTextRevision()
                ))
            }
        } else {
            for index in functionSections.indices {
                let isCollapsed = collapsedIDs.contains(functions[index].id)
                functionSections[index].titleField.stringValue = functions[index].title
                functionSections[index].textView.isHidden = isCollapsed
                updateCollapseButton(for: index, isCollapsed: isCollapsed)
                let current = functionSections[index]
                functionSections[index] = FunctionSection(
                    function: functions[index],
                    titleField: current.titleField,
                    textView: current.textView,
                    cacheHitButton: current.cacheHitButton,
                    collapseButton: current.collapseButton,
                    copyButton: current.copyButton,
                    dividerView: current.dividerView,
                    isLoading: current.isLoading,
                    isCollapsed: isCollapsed,
                    isCacheHit: current.isCacheHit,
                    textRevision: current.textRevision
                )
            }
        }
    }

    @discardableResult
    private func updateFunctionSection(
        functionID: UUID,
        text: String,
        isFinal: Bool,
        isCacheHit: Bool
    ) -> Bool {
        guard let index = functionSections.firstIndex(where: { $0.function.id == functionID }) else {
            return false
        }
        var section = functionSections[index]
        var didChange = false
        let currentText = section.textView.string
        if currentText != text {
            if let delta = streamingDelta(current: currentText, incoming: text), !delta.isEmpty {
                appendResultText(in: section.textView, delta: delta)
            } else {
                replaceResultText(in: section.textView, with: text)
            }
            section.textRevision = takeNextTextRevision()
            didChange = true
            applyStreamingFadeIfNeeded(to: section.textView, functionID: functionID, isFinal: isFinal)
        }
        let previousLoading = section.isLoading
        if isFinal {
            section.isLoading = false
        } else {
            let hasContent = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            section.isLoading = !hasContent
        }
        if section.isLoading != previousLoading {
            didChange = true
        }
        let previousCacheHit = section.isCacheHit
        if isCacheHit {
            section.isCacheHit = true
        }
        if section.isCacheHit != previousCacheHit {
            didChange = true
        }
        functionSections[index] = section
        if !functionSections.contains(where: { $0.isLoading }) {
            stopLoadingAnimation()
        }
        return didChange
    }

    private func applyResultTextViewStyle(_ textView: PopupResultTextView, font: NSFont) {
        textView.font = font
        textView.textColor = .labelColor
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        let fullRange = NSRange(location: 0, length: textView.string.utf16.count)
        if fullRange.length > 0, let storage = textView.textStorage {
            storage.beginEditing()
            storage.setAttributes(textView.typingAttributes, range: fullRange)
            storage.endEditing()
        }
    }

    private func replaceResultText(in textView: PopupResultTextView, with text: String) {
        textView.string = text
    }

    private func appendResultText(in textView: PopupResultTextView, delta: String) {
        guard !delta.isEmpty else {
            return
        }
        let attributes = textView.typingAttributes
        let appended = NSAttributedString(string: delta, attributes: attributes)
        textView.textStorage?.append(appended)
    }

    private func streamingDelta(current: String, incoming: String) -> String? {
        guard !current.isEmpty, incoming.count >= current.count, incoming.hasPrefix(current) else {
            return nil
        }
        return String(incoming.dropFirst(current.count))
    }

    private func takeNextTextRevision() -> UInt64 {
        defer { nextTextRevision += 1 }
        return nextTextRevision
    }

    private func measuredTextSize(for textField: NSTextField, maxWidth: CGFloat, revision: UInt64) -> CGSize {
        let key = ObjectIdentifier(textField)
        let fontPointSize = textField.font?.pointSize ?? baseTextSize
        if let cached = textMeasurementCache[key],
           cached.revision == revision,
           abs(cached.maxWidth - maxWidth) < 0.5,
           abs(cached.fontPointSize - fontPointSize) < 0.01 {
            return cached.size
        }
        let font = textField.font ?? NSFont.systemFont(ofSize: baseTextSize, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let attributed = NSAttributedString(string: textField.stringValue, attributes: attributes)
        let boundingRect = attributed.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let measured = CGSize(width: ceil(boundingRect.width), height: ceil(boundingRect.height) + 4)
        textMeasurementCache[key] = TextMeasurementCacheEntry(
            revision: revision,
            maxWidth: maxWidth,
            fontPointSize: fontPointSize,
            size: measured
        )
        return measured
    }

    private func measuredTextSize(for textView: PopupResultTextView, maxWidth: CGFloat, revision: UInt64) -> CGSize {
        let key = ObjectIdentifier(textView)
        let fontPointSize = textView.font?.pointSize ?? baseTextSize
        if let cached = textMeasurementCache[key],
           cached.revision == revision,
           abs(cached.maxWidth - maxWidth) < 0.5,
           abs(cached.fontPointSize - fontPointSize) < 0.01 {
            return cached.size
        }
        let measured: CGSize
        if let textContainer = textView.textContainer,
           let layoutManager = textView.layoutManager {
            textContainer.containerSize = CGSize(width: maxWidth, height: .greatestFiniteMagnitude)
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            measured = CGSize(width: ceil(usedRect.width), height: ceil(usedRect.height) + 4)
        } else {
            let font = textView.font ?? NSFont.systemFont(ofSize: baseTextSize, weight: .medium)
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let attributed = NSAttributedString(string: textView.string, attributes: attributes)
            let boundingRect = attributed.boundingRect(
                with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            measured = CGSize(width: ceil(boundingRect.width), height: ceil(boundingRect.height) + 4)
        }
        textMeasurementCache[key] = TextMeasurementCacheEntry(
            revision: revision,
            maxWidth: maxWidth,
            fontPointSize: fontPointSize,
            size: measured
        )
        return measured
    }

    private func applyStreamingFadeIfNeeded(to textView: PopupResultTextView, functionID: UUID, isFinal: Bool) {
        guard !isFinal else {
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if let last = streamFadeTimestamps[functionID], now - last < streamingFadeInterval {
            return
        }
        streamFadeTimestamps[functionID] = now
        textView.wantsLayer = true
        let transition = CATransition()
        transition.type = .fade
        transition.duration = streamingFadeDuration
        transition.timingFunction = CAMediaTimingFunction(name: .easeOut)
        textView.layer?.add(transition, forKey: "streamFade")
    }

    private func layoutContent(near location: CGPoint?) -> CGSize {

        let padding = CGSize(width: 10, height: 8)
        let minWidth: CGFloat = 120
        let controlsHeight: CGFloat = 18
        let controlsSpacing: CGFloat = 6
        let headerLabelSpacing: CGFloat = 8
        let headerLabelExtra: CGFloat = 6
        let headerButtonSize: CGFloat = 18
        let headerButtonSpacing: CGFloat = 6
        let preferredMaxWidth = AppPreferences.popupMaxWidth()
        let preferredMaxHeight = AppPreferences.popupMaxHeight()
        let screen = location.flatMap { screenContaining($0) } ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? .zero
        let maxHeightLimit = max(120, min(preferredMaxHeight, visibleFrame.height - 24))
        let titleTextSpacing: CGFloat = 2
        let dividerHeight: CGFloat = 1
        let dividerSpacing: CGFloat = 6
        let scrollerClearance: CGFloat = 12
        let sectionButtonSize: CGFloat = 16
        let sectionButtonSpacing: CGFloat = 4
        let paddingLeft = padding.width
        let originalSectionButtonCount = 2

        func sectionHeaderButtonsWidth(for section: FunctionSection) -> CGFloat {
            let buttonCount = section.isCacheHit ? 3 : 2
            return CGFloat(buttonCount) * sectionButtonSize + CGFloat(buttonCount) * sectionButtonSpacing
        }

        let titleFont = originalTitleField.font ?? NSFont.systemFont(ofSize: 11, weight: .semibold)
        let titleAttributes: [NSAttributedString.Key: Any] = [.font: titleFont]

        let modelText = AppPreferences.model()
        modelLabelField.stringValue = modelText
        let modelFont = modelLabelField.font ?? NSFont.systemFont(ofSize: baseTitleSize, weight: .semibold)
        let modelAttributes: [NSAttributedString.Key: Any] = [.font: modelFont]
        let modelWidth = ceil(max(
            modelLabelField.intrinsicContentSize.width,
            (modelText as NSString).size(withAttributes: modelAttributes).width
        ))
        let headerVisibleButtons = actionButtons.filter { !$0.isHidden }
        let headerButtonsWidth = CGFloat(headerVisibleButtons.count) * headerButtonSize
            + CGFloat(max(0, headerVisibleButtons.count - 1)) * headerButtonSpacing
        let headerMinWidth = paddingLeft + modelWidth + headerLabelSpacing + headerButtonsWidth + padding.width + headerLabelExtra
        let maxWidthLimit = max(minWidth, min(max(preferredMaxWidth, headerMinWidth), visibleFrame.width - 24))

        func measureLayout(
            maxWidth: CGFloat,
            paddingRight: CGFloat
        ) -> (contentWidth: CGFloat, contentHeight: CGFloat, sizes: (CGSize, CGSize, [CGSize], [CGSize])) {
            let originalTitleSize = (originalTitleField.stringValue as NSString).size(withAttributes: titleAttributes)
            let textMaxWidth = maxWidth - paddingLeft - paddingRight
            let originalTextSize = originalIsCollapsed
                ? .zero
                : measuredTextSize(for: originalTextField, maxWidth: textMaxWidth, revision: originalTextRevision)
            var sectionTitleSizes: [CGSize] = []
            var sectionTextSizes: [CGSize] = []
            sectionTitleSizes.reserveCapacity(functionSections.count)
            sectionTextSizes.reserveCapacity(functionSections.count)
            for section in functionSections {
                let titleSize = (section.titleField.stringValue as NSString).size(withAttributes: titleAttributes)
                let textSizeValue = section.isCollapsed
                    ? .zero
                    : measuredTextSize(for: section.textView, maxWidth: textMaxWidth, revision: section.textRevision)
                sectionTitleSizes.append(titleSize)
                sectionTextSizes.append(textSizeValue)
            }

            let originalTitleWidth = originalTitleSize.width
                + CGFloat(originalSectionButtonCount) * sectionButtonSize
                + CGFloat(originalSectionButtonCount) * sectionButtonSpacing
            var contentTextWidth = max(originalTitleWidth, originalTextSize.width)
            for index in sectionTitleSizes.indices {
                let sectionTitleWidth = sectionTitleSizes[index].width + sectionHeaderButtonsWidth(for: functionSections[index])
                let sectionWidth = max(sectionTitleWidth, sectionTextSizes[index].width)
                contentTextWidth = max(contentTextWidth, sectionWidth)
            }
            let contentWidth = max(
                minWidth,
                min(maxWidth, max(contentTextWidth + paddingLeft + paddingRight, headerMinWidth))
            )
            let adjustedTextMaxWidth = contentWidth - paddingLeft - paddingRight
            if abs(adjustedTextMaxWidth - textMaxWidth) > 0.5 {
                let adjustedOriginalTextSize = originalIsCollapsed
                    ? .zero
                    : measuredTextSize(for: originalTextField, maxWidth: adjustedTextMaxWidth, revision: originalTextRevision)
                var adjustedSectionTextSizes: [CGSize] = []
                adjustedSectionTextSizes.reserveCapacity(functionSections.count)
                for section in functionSections {
                    let adjustedSize = section.isCollapsed
                        ? .zero
                        : measuredTextSize(for: section.textView, maxWidth: adjustedTextMaxWidth, revision: section.textRevision)
                    adjustedSectionTextSizes.append(adjustedSize)
                }
                return (
                    contentWidth,
                    contentHeight(
                        originalTitleSize: originalTitleSize,
                        originalTextSize: adjustedOriginalTextSize,
                        sectionTitleSizes: sectionTitleSizes,
                        sectionTextSizes: adjustedSectionTextSizes,
                        titleTextSpacing: titleTextSpacing,
                        dividerHeight: dividerHeight,
                        dividerSpacing: dividerSpacing,
                        padding: padding
                    ),
                    (originalTitleSize, adjustedOriginalTextSize, sectionTitleSizes, adjustedSectionTextSizes)
                )
            }

            let height = contentHeight(
                originalTitleSize: originalTitleSize,
                originalTextSize: originalTextSize,
                sectionTitleSizes: sectionTitleSizes,
                sectionTextSizes: sectionTextSizes,
                titleTextSpacing: titleTextSpacing,
                dividerHeight: dividerHeight,
                dividerSpacing: dividerSpacing,
                padding: padding
            )
            return (contentWidth, height, (originalTitleSize, originalTextSize, sectionTitleSizes, sectionTextSizes))
        }

        func contentHeight(
            originalTitleSize: CGSize,
            originalTextSize: CGSize,
            sectionTitleSizes: [CGSize],
            sectionTextSizes: [CGSize],
            titleTextSpacing: CGFloat,
            dividerHeight: CGFloat,
            dividerSpacing: CGFloat,
            padding: CGSize
        ) -> CGFloat {
            let originalTitleHeight = ceil(originalTitleSize.height)
            let originalTextHeight = originalIsCollapsed ? 0 : max(ceil(originalTextSize.height), 16)
            let originalSpacing = originalIsCollapsed ? 0 : titleTextSpacing
            var height = padding.height * 2 + 4
                + originalTitleHeight
                + originalSpacing
                + originalTextHeight
            for index in sectionTitleSizes.indices {
                let titleHeight = ceil(sectionTitleSizes[index].height)
                let isCollapsed = functionSections[index].isCollapsed
                let textHeight = isCollapsed ? 0 : max(ceil(sectionTextSizes[index].height), 16)
                let spacing = isCollapsed ? 0 : titleTextSpacing
                height += dividerSpacing
                    + dividerHeight
                    + dividerSpacing
                    + titleHeight
                    + spacing
                    + textHeight
            }
            return height
        }

        var paddingRight = padding.width
        let targetMaxWidth = maxWidthLimit
        var measurement = measureLayout(maxWidth: targetMaxWidth, paddingRight: paddingRight)

        let needsVerticalScroll = measurement.contentHeight > maxHeightLimit
        if needsVerticalScroll {
            paddingRight = padding.width + scrollerClearance
            measurement = measureLayout(maxWidth: targetMaxWidth, paddingRight: paddingRight)
        }

        let contentWidth = measurement.contentWidth
        let originalTitleSize = measurement.sizes.0
        let originalTextSize = measurement.sizes.1
        let sectionTitleSizes = measurement.sizes.2
        let sectionTextSizes = measurement.sizes.3
        let contentHeight = measurement.contentHeight
        let visibleHeight = min(contentHeight, maxHeightLimit)

        let titleX = paddingLeft
        let textX = paddingLeft
        let availableWidth = contentWidth - paddingLeft - paddingRight
        originalTextField.preferredMaxLayoutWidth = availableWidth
        for section in functionSections {
            section.textView.textContainer?.containerSize = CGSize(width: availableWidth, height: .greatestFiniteMagnitude)
        }

        var y = contentHeight - padding.height - ceil(originalTitleSize.height)

        originalTitleField.frame = NSRect(
            x: titleX,
            y: y,
            width: max(
                0,
                availableWidth
                    - CGFloat(originalSectionButtonCount) * sectionButtonSize
                    - CGFloat(originalSectionButtonCount) * sectionButtonSpacing
            ),
            height: ceil(originalTitleSize.height)
        )
        let originalCollapseButtonX = paddingLeft + availableWidth - sectionButtonSize
        let originalCopyButtonX = originalCollapseButtonX - sectionButtonSpacing - sectionButtonSize
        let originalButtonY = y + max(0, (ceil(originalTitleSize.height) - sectionButtonSize) * 0.5)
        originalCollapseButton.frame = NSRect(
            x: originalCollapseButtonX,
            y: originalButtonY,
            width: sectionButtonSize,
            height: sectionButtonSize
        )
        originalCopyButton.frame = NSRect(
            x: originalCopyButtonX,
            y: originalButtonY,
            width: sectionButtonSize,
            height: sectionButtonSize
        )
        let originalTextHeight = originalIsCollapsed ? 0 : max(ceil(originalTextSize.height), 16)
        let originalSpacing = originalIsCollapsed ? 0 : titleTextSpacing
        y -= originalSpacing + originalTextHeight

        originalTextField.frame = NSRect(
            x: textX,
            y: y,
            width: availableWidth,
            height: originalTextHeight
        )

        for index in functionSections.indices {
            let section = functionSections[index]
            let titleSize = sectionTitleSizes[index]
            let textSizeValue = sectionTextSizes[index]
            y -= dividerSpacing + dividerHeight
            section.dividerView.frame = NSRect(
                x: paddingLeft,
                y: y,
                width: availableWidth,
                height: dividerHeight
            )
            y -= dividerSpacing + ceil(titleSize.height)
            section.titleField.frame = NSRect(
                x: titleX,
                y: y,
                width: max(0, availableWidth - sectionHeaderButtonsWidth(for: section)),
                height: ceil(titleSize.height)
            )
            let collapseButtonX = paddingLeft + availableWidth - sectionButtonSize
            let copyButtonX = collapseButtonX - sectionButtonSpacing - sectionButtonSize
            let cacheButtonX = copyButtonX - sectionButtonSpacing - sectionButtonSize
            let buttonY = y + max(0, (ceil(titleSize.height) - sectionButtonSize) * 0.5)
            section.collapseButton.frame = NSRect(
                x: collapseButtonX,
                y: buttonY,
                width: sectionButtonSize,
                height: sectionButtonSize
            )
            section.copyButton.frame = NSRect(
                x: copyButtonX,
                y: buttonY,
                width: sectionButtonSize,
                height: sectionButtonSize
            )
            if section.isCacheHit {
                section.cacheHitButton.isHidden = false
                section.cacheHitButton.frame = NSRect(
                    x: cacheButtonX,
                    y: buttonY,
                    width: sectionButtonSize,
                    height: sectionButtonSize
                )
            } else {
                section.cacheHitButton.isHidden = true
            }
            let isCollapsed = section.isCollapsed
            let textHeight = isCollapsed ? 0 : max(ceil(textSizeValue.height), 16)
            let spacing = isCollapsed ? 0 : titleTextSpacing
            y -= spacing + textHeight
            section.textView.frame = NSRect(
                x: textX,
                y: y,
                width: availableWidth,
                height: textHeight
            )
        }

        let headerHeight = controlsHeight + controlsSpacing
        documentView.frame = NSRect(origin: .zero, size: CGSize(width: contentWidth, height: contentHeight))
        contentView.frame = NSRect(origin: .zero, size: CGSize(width: contentWidth, height: visibleHeight + headerHeight))
        scrollView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: visibleHeight)
        headerView.frame = NSRect(x: 0, y: visibleHeight, width: contentWidth, height: headerHeight)
        headerDividerView.frame = NSRect(
            x: paddingLeft,
            y: visibleHeight,
            width: availableWidth,
            height: 1
        )
        scrollView.hasVerticalScroller = needsVerticalScroll
        let buttonSize: CGFloat = 18
        let buttonSpacing: CGFloat = 6
        let layoutVisibleButtons = actionButtons.filter { !$0.isHidden }
        let buttonsWidth = CGFloat(layoutVisibleButtons.count) * buttonSize + CGFloat(max(0, layoutVisibleButtons.count - 1)) * buttonSpacing
        let buttonsX = max(paddingLeft, contentWidth - padding.width - buttonsWidth)
        let buttonsY = (headerHeight - buttonSize) * 0.5
        for (index, button) in layoutVisibleButtons.enumerated() {
            let x = buttonsX + CGFloat(index) * (buttonSize + buttonSpacing)
            button.frame = NSRect(x: x, y: buttonsY, width: buttonSize, height: buttonSize)
        }
        let modelSize = (modelText as NSString).size(withAttributes: modelAttributes)
        let labelMaxWidth = max(0, buttonsX - paddingLeft - headerLabelSpacing)
        let labelHeight = ceil(modelSize.height)
        let labelY = (headerHeight - labelHeight) * 0.5
        modelLabelField.frame = NSRect(x: paddingLeft, y: labelY, width: labelMaxWidth, height: labelHeight)
        return CGSize(width: contentWidth, height: visibleHeight + headerHeight)
    }

    private func setWindowFrame(contentSize: CGSize, near location: CGPoint, animated: Bool) {
        let offset = CGPoint(x: 12, y: -12)
        let origin = CGPoint(
            x: location.x + offset.x,
            y: location.y - contentSize.height + offset.y
        )
        let clampedOrigin = clampOrigin(origin, for: contentSize, near: location)
        let frame = NSRect(origin: clampedOrigin, size: contentSize)
        if let last = lastWindowFrame,
           abs(last.origin.x - frame.origin.x) < 0.5,
           abs(last.origin.y - frame.origin.y) < 0.5,
           abs(last.size.width - frame.size.width) < 0.5,
           abs(last.size.height - frame.size.height) < 0.5 {
            return
        }
        if animated {
            window.animator().setFrame(frame, display: true)
        } else {
            window.setFrame(frame, display: true)
        }
        lastWindowFrame = frame
    }

    private func scheduleLayoutUpdate(near location: CGPoint, animated: Bool, streaming: Bool = false) {
        guard window.isVisible else {
            return
        }
        pendingLayoutLocation = location
        pendingLayoutAnimate = pendingLayoutAnimate || animated
        if animated {
            performPendingLayoutUpdate()
            return
        }
        if layoutUpdateTimer == nil {
            let interval = streaming ? streamingLayoutDebounceInterval : layoutDebounceInterval
            layoutUpdateTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.performPendingLayoutUpdate()
                }
            }
        }
    }

    private func performPendingLayoutUpdate() {
        guard let location = pendingLayoutLocation else {
            return
        }
        let animate = pendingLayoutAnimate
        pendingLayoutAnimate = false
        layoutUpdateTimer?.invalidate()
        layoutUpdateTimer = nil
        let contentSize = layoutContent(near: location)
        if animate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                setWindowFrame(contentSize: contentSize, near: location, animated: true)
            }
        } else {
            setWindowFrame(contentSize: contentSize, near: location, animated: false)
        }
    }

    private func cancelPendingLayoutUpdate() {
        layoutUpdateTimer?.invalidate()
        layoutUpdateTimer = nil
        pendingLayoutLocation = nil
        pendingLayoutAnimate = false
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

    private func resetContentForNextShow() {
        currentRequestID = nil
        lastAnchorLocation = nil
        originalTextField.stringValue = ""
        originalTextRevision = takeNextTextRevision()
        streamFadeTimestamps.removeAll()
        for index in functionSections.indices {
            replaceResultText(in: functionSections[index].textView, with: "")
            functionSections[index].isLoading = false
            functionSections[index].isCacheHit = false
            functionSections[index].textRevision = takeNextTextRevision()
        }
        updateActionButtons()
    }

    private func tickLoadingAnimation() {
        loadingDotCount = (loadingDotCount + 1) % 4
        updateLoadingText()
    }

    private func updateLoadingText() {
        let dots = String(repeating: "·", count: loadingDotCount)
        let loadingText = UIStrings.Popup.processingPrefix + dots
        for index in functionSections.indices where functionSections[index].isLoading {
            let existing = functionSections[index].textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if existing.isEmpty {
                replaceResultText(in: functionSections[index].textView, with: loadingText)
                functionSections[index].textRevision = takeNextTextRevision()
            }
        }
    }

    private func updateActionButtons() {
        let hasAnyResult = functionSections.contains {
            !$0.isLoading && !$0.textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        copyAllButton.isEnabled = hasAnyResult
        let enabledAlpha: CGFloat = 1
        let disabledAlpha: CGFloat = 0.4
        let originalHasText = !originalTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        retryButton.isEnabled = originalHasText
        retryButton.alphaValue = originalHasText ? enabledAlpha : disabledAlpha
        copyAllButton.alphaValue = hasAnyResult ? enabledAlpha : disabledAlpha
        originalCopyButton.isEnabled = originalHasText
        originalCopyButton.alphaValue = originalHasText ? enabledAlpha : disabledAlpha
        for section in functionSections {
            let hasResult = !section.isLoading
                && !section.textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            section.copyButton.isEnabled = hasResult
            section.copyButton.alphaValue = hasResult ? enabledAlpha : disabledAlpha
            section.cacheHitButton.isHidden = !section.isCacheHit
            section.cacheHitButton.isEnabled = true
            section.cacheHitButton.alphaValue = section.isCacheHit ? enabledAlpha : 0
        }
    }

    private func handleHover(_ isHovering: Bool, for button: HoverableIconButton) {
        if isHovering {
            hoveredButton = button
            scheduleTooltip(for: button)
        } else if hoveredButton === button {
            hideTooltip()
        }
    }

    private func scheduleTooltip(for button: HoverableIconButton) {
        tooltipTimer?.invalidate()
        let delay = AppPreferences.popupTooltipDelayMs() / 1000
        tooltipTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self, weak button] _ in
            Task { @MainActor in
                guard let self, let button, self.hoveredButton === button else {
                    return
                }
                self.showTooltip(for: button)
            }
        }
    }

    private func showTooltip(for button: HoverableIconButton) {
        showTooltip(text: button.tooltipText, for: button)
    }

    private func hideTooltip() {
        tooltipTimer?.invalidate()
        tooltipTimer = nil
        copyFeedbackTimer?.invalidate()
        copyFeedbackTimer = nil
        hoveredButton = nil
        tooltipWindow.hide()
    }

    private func showTooltip(text: String, for button: HoverableIconButton) {
        guard let window = button.window else {
            return
        }
        let rectInWindow = button.convert(button.bounds, to: nil)
        let rectOnScreen = window.convertToScreen(rectInWindow)
        let scale = PopupFontPreferences.load() / baseTextSize
        let fontSize = baseTooltipSize * scale
        tooltipWindow.show(text: text, near: rectOnScreen, fontSize: fontSize)
    }

    private func showCopyFeedback(text: String) {
        copyFeedbackTimer?.invalidate()
        copyFeedbackTimer = nil
        hoveredButton = nil
        tooltipTimer?.invalidate()
        tooltipTimer = nil
        let popupFrame = window.frame
        let scale = PopupFontPreferences.load() / baseTextSize
        let fontSize = baseTooltipSize * scale
        tooltipWindow.showCentered(text: text, in: popupFrame, fontSize: fontSize)
        copyFeedbackTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.tooltipWindow.hide()
            }
        }
    }

    private func handleCopyShortcut(includeOriginal: Bool) -> Bool {
        copyCombinedResults(includeOriginal: includeOriginal)
    }

    @discardableResult
    private func copyCombinedResults(includeOriginal: Bool) -> Bool {
        hideTooltip()
        let combined = combinedResultText(includeOriginal: includeOriginal)
        guard copyToPasteboard(combined) else {
            return false
        }
        let successText = includeOriginal
            ? UIStrings.Popup.copyAllWithOriginalSuccess
            : UIStrings.Popup.copyAllWithoutOriginalSuccess
        showCopyFeedback(text: successText)
        return true
    }

    private func combinedResultText(includeOriginal: Bool) -> String {
        var sections: [String] = []
        if includeOriginal {
            let original = originalTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !original.isEmpty {
                sections.append("\(UIStrings.Popup.originalTitle)\n\(original)")
            }
        }
        for section in functionSections where !section.isLoading {
            let result = section.textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !result.isEmpty else {
                continue
            }
            let title = section.titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayTitle = title.isEmpty ? UIStrings.Popup.untitledFunction : title
            sections.append("\(displayTitle)\n\(result)")
        }
        return sections.joined(separator: "\n\n")
    }

    @objc private func handleCopyAll() {
        copyCombinedResults(includeOriginal: true)
    }

    @objc private func handleCopyOriginal() {
        hideTooltip()
        let text = originalTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if copyToPasteboard(text) {
            showCopyFeedback(text: UIStrings.Popup.copyResultSuccess)
        }
    }

    @objc private func handleToggleOriginalCollapse() {
        hideTooltip()
        let newValue = !originalIsCollapsed
        setOriginalCollapsed(isCollapsed: newValue, persist: true)
    }

    @objc private func handleCopySection(_ sender: HoverableIconButton) {
        hideTooltip()
        guard let section = functionSections.first(where: { $0.copyButton === sender }),
              !section.isLoading else {
            return
        }
        let text = section.textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if copyToPasteboard(text) {
            showCopyFeedback(text: UIStrings.Popup.copyResultSuccess)
        }
    }

    @objc private func handleToggleSectionCollapse(_ sender: HoverableIconButton) {
        hideTooltip()
        guard let index = functionSections.firstIndex(where: { $0.collapseButton === sender }) else {
            return
        }
        let newValue = !functionSections[index].isCollapsed
        setSectionCollapsed(index: index, isCollapsed: newValue, persist: true)
    }

    @objc private func handleOpenPreferences() {
        hideTooltip()
        onOpenPreferences?()
    }

    @objc private func handleRetry() {
        hideTooltip()
        let text = originalTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return
        }
        let retryAnchor = CGPoint(
            x: window.frame.minX - 12,
            y: window.frame.maxY + 12
        )
        onRetry?(text, retryAnchor)
    }

    @objc private func handleSectionCacheHitIndicator(_ _: HoverableIconButton) {
        hideTooltip()
        return
    }

    private func copyToPasteboard(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(trimmed, forType: .string)
    }

    private static func makeIconButton(
        symbolName: String,
        toolTip: String,
        target: AnyObject?,
        action: Selector
    ) -> HoverableIconButton {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: toolTip)
        image?.isTemplate = true
        let button = HoverableIconButton(image: image ?? NSImage(), target: target, action: action)
        button.isBordered = false
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = nil
        button.tooltipText = toolTip
        button.setAccessibilityLabel(toolTip)
        button.focusRingType = .none
        return button
    }

    private func updateOriginalCollapseButton() {
        let toolTip = originalIsCollapsed ? UIStrings.Popup.expandResult : UIStrings.Popup.collapseResult
        let symbolName = originalIsCollapsed ? "chevron.right" : "chevron.down"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: toolTip)
        image?.isTemplate = true
        originalCollapseButton.image = image
        originalCollapseButton.tooltipText = toolTip
        originalCollapseButton.setAccessibilityLabel(toolTip)
    }

    private func setOriginalCollapsed(isCollapsed: Bool, persist: Bool) {
        originalIsCollapsed = isCollapsed
        originalTextField.isHidden = isCollapsed
        updateOriginalCollapseButton()
        if persist {
            AppPreferences.setPopupOriginalCollapsed(isCollapsed)
        }
        refreshLayout()
    }

    private func updateCollapseButton(for index: Int, isCollapsed: Bool? = nil) {
        let collapsed = isCollapsed ?? functionSections[index].isCollapsed
        let toolTip = collapsed ? UIStrings.Popup.expandResult : UIStrings.Popup.collapseResult
        let symbolName = collapsed ? "chevron.right" : "chevron.down"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: toolTip)
        image?.isTemplate = true
        functionSections[index].collapseButton.image = image
        functionSections[index].collapseButton.tooltipText = toolTip
        functionSections[index].collapseButton.setAccessibilityLabel(toolTip)
    }

    private func setSectionCollapsed(index: Int, isCollapsed: Bool, persist: Bool) {
        functionSections[index].isCollapsed = isCollapsed
        functionSections[index].textView.isHidden = isCollapsed
        updateCollapseButton(for: index, isCollapsed: isCollapsed)
        if persist {
            AppPreferences.setPopupFunctionCollapsed(functionSections[index].function.id, isCollapsed: isCollapsed)
        }
        refreshLayout()
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
        dismissPopup()
    }

    func dismissIfClickOutside(_ location: CGPoint) {
        guard window.isVisible else {
            return
        }
        if !isLocationInsideWindow(location) {
            dismissPopup()
        }
    }

    private func dismissPopup() {
        cancelPendingLayoutUpdate()
        stopLoadingAnimation()
        hideTooltip()
        window.orderOut(nil)
        resetContentForNextShow()
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

final class PopupWindow: NSWindow {
    var onDismiss: (() -> Void)?
    var onCopyShortcut: ((Bool) -> Bool)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let includeOriginal = includeOriginalIfCopyShortcut(event),
           onCopyShortcut?(includeOriginal) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == CGKeyCode(kVK_Escape) {
            onDismiss?()
            return
        }
        super.keyDown(with: event)
    }

    private func includeOriginalIfCopyShortcut(_ event: NSEvent) -> Bool? {
        guard let key = event.charactersIgnoringModifiers?.lowercased(), key == "c" else {
            return nil
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch flags {
        case .command:
            return false
        case [.command, .shift]:
            return true
        default:
            return nil
        }
    }
}

@MainActor
let forceClickSelectionPopup = ForceClickSelectionPopup()
