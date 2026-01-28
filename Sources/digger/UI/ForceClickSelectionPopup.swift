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
        window?.performDrag(with: event)
    }
}

@MainActor
final class ForceClickSelectionPopup {
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

    func updateTranslation(_ translation: String, for requestID: UUID, near location: CGPoint, isFinal: Bool) {
        guard currentRequestID == requestID else {
            return
        }
        stopLoadingAnimation()
        let updatedTranslation = isFinal
            ? translation.trimmingCharacters(in: .whitespacesAndNewlines)
            : translation
        lastAnchorLocation = location
        isShowingTranslation = true
        isShowingLoading = false
        translationTextField.stringValue = updatedTranslation
        let contentSize = layoutContent(showTranslation: isShowingTranslation, showLoading: isShowingLoading, near: location)
        if isFinal {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                setWindowFrame(contentSize: contentSize, near: location, animated: true)
            }
        } else {
            setWindowFrame(contentSize: contentSize, near: location, animated: false)
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

        let previousScrollOrigin = scrollView.contentView.bounds.origin

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
        let maxScrollY = max(0, contentHeight - visibleHeight)
        let bottomY = scrollView.contentView.isFlipped ? maxScrollY : 0
        scrollView.contentView.scroll(to: NSPoint(x: previousScrollOrigin.x, y: bottomY))
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

final class PopupWindow: NSWindow {
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
let forceClickSelectionPopup = ForceClickSelectionPopup()
