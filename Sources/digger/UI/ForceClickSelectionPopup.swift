import AppKit
import Carbon
import Foundation
import QuartzCore

struct PopupLayoutDefinition: Equatable, Sendable {
    let id: UUID
    let title: String
    let isTranslation: Bool
}

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
        let x = anchor.midX - width * 0.5
        let y = anchor.minY - height - 6
        setFrameOrigin(NSPoint(x: x, y: y))
        orderFront(nil)
    }

    func hide() {
        orderOut(nil)
    }
}

@MainActor
final class ForceClickSelectionPopup {
    private let window: PopupWindow
    private let originalTitleField: NSTextField
    private let originalTextField: NSTextField
    private let loadingTextField: NSTextField
    private let contentView: DraggableContentView
    private let headerView: NSView
    private let scrollView: DraggableScrollView
    private let documentView: NSView
    private let copyTranslationButton: HoverableIconButton
    private let copyAllButton: HoverableIconButton
    private let preferencesButton: HoverableIconButton
    private let actionButtons: [HoverableIconButton]
    private let tooltipWindow: HoverTooltipWindow
    private var tooltipTimer: Timer?
    private weak var hoveredButton: HoverableIconButton?
    var onOpenPreferences: (() -> Void)?
    private var loadingTimer: Timer?
    private var loadingDotCount = 0
    private var currentRequestID: UUID?
    private var lastAnchorLocation: CGPoint?
    private var isShowingLoading = false
    private var pendingLayoutIDs = Set<UUID>()
    private let baseTitleSize: CGFloat = 11
    private let baseTextSize: CGFloat = 12
    private let baseLoadingSize: CGFloat = 11
    private let baseTooltipSize: CGFloat = 11
    private var layoutSections: [LayoutSection] = []

    private struct LayoutSection {
        let id: UUID
        let titleField: NSTextField
        let textField: NSTextField
        let dividerView: NSView
        let isTranslation: Bool
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
        originalTextField.isSelectable = false
        originalTextField.lineBreakMode = .byWordWrapping
        originalTextField.maximumNumberOfLines = 0
        originalTextField.cell?.wraps = true
        originalTextField.cell?.usesSingleLineMode = false

        loadingTextField = NSTextField(labelWithString: "")
        loadingTextField.font = NSFont.systemFont(ofSize: baseLoadingSize, weight: .regular)
        loadingTextField.textColor = .secondaryLabelColor
        loadingTextField.backgroundColor = .clear
        loadingTextField.isEditable = false
        loadingTextField.isSelectable = false
        loadingTextField.lineBreakMode = .byTruncatingTail

        copyTranslationButton = ForceClickSelectionPopup.makeIconButton(
            symbolName: "doc.text",
            toolTip: UIStrings.Popup.copyTranslation,
            target: nil,
            action: #selector(handleCopyTranslation)
        )
        copyAllButton = ForceClickSelectionPopup.makeIconButton(
            symbolName: "doc.on.doc",
            toolTip: UIStrings.Popup.copyAll,
            target: nil,
            action: #selector(handleCopyAll)
        )
        preferencesButton = ForceClickSelectionPopup.makeIconButton(
            symbolName: "gearshape",
            toolTip: UIStrings.Popup.openPreferences,
            target: nil,
            action: #selector(handleOpenPreferences)
        )
        actionButtons = [copyTranslationButton, copyAllButton, preferencesButton]
        tooltipWindow = HoverTooltipWindow()

        contentView = DraggableContentView()
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor
        contentView.layer?.cornerRadius = 8
        headerView = NSView()
        documentView = NSView()
        documentView.addSubview(originalTitleField)
        documentView.addSubview(originalTextField)
        documentView.addSubview(loadingTextField)

        scrollView = DraggableScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.documentView = documentView
        headerView.addSubview(copyTranslationButton)
        headerView.addSubview(copyAllButton)
        headerView.addSubview(preferencesButton)
        contentView.addSubview(scrollView)
        contentView.addSubview(headerView)

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

        for button in actionButtons {
            button.target = self
            button.onHover = { [weak self, weak button] isHovering in
                guard let self, let button else {
                    return
                }
                self.handleHover(isHovering, for: button)
            }
        }

        applyPopupTextSize(PopupFontPreferences.load())
        applyStrings()
        updateActionButtons()
    }

    func showLoading(original: String, layouts: [PopupLayoutDefinition], near location: CGPoint, requestID: UUID) {
        let trimmedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOriginal.isEmpty else {
            return
        }

        currentRequestID = requestID
        lastAnchorLocation = location
        originalTextField.stringValue = trimmedOriginal
        configureLayoutSections(layouts)
        pendingLayoutIDs = Set(layouts.map { $0.id })
        isShowingLoading = !pendingLayoutIDs.isEmpty
        if isShowingLoading {
            startLoadingAnimation()
        } else {
            stopLoadingAnimation()
        }
        updateActionButtons()
        let contentSize = layoutContent(showLoading: isShowingLoading, near: location)
        setWindowFrame(contentSize: contentSize, near: location, animated: false)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func updateLayoutResult(_ result: String, for layoutID: UUID, requestID: UUID, near location: CGPoint, isFinal: Bool) {
        guard currentRequestID == requestID else {
            return
        }
        guard let section = layoutSections.first(where: { $0.id == layoutID }) else {
            return
        }
        let updatedResult = isFinal
            ? result.trimmingCharacters(in: .whitespacesAndNewlines)
            : result
        section.textField.stringValue = updatedResult
        lastAnchorLocation = location
        if !isFinal, layoutSections.count == 1, pendingLayoutIDs.contains(layoutID) {
            pendingLayoutIDs.remove(layoutID)
            isShowingLoading = false
            stopLoadingAnimation()
        }
        if isFinal {
            pendingLayoutIDs.remove(layoutID)
            if pendingLayoutIDs.isEmpty {
                isShowingLoading = false
                stopLoadingAnimation()
            }
        }
        updateActionButtons()
        let contentSize = layoutContent(showLoading: isShowingLoading, near: location)
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

    func applyPopupTextSize(_ textSize: CGFloat) {
        let clampedSize = PopupFontPreferences.clamp(textSize)
        let scale = clampedSize / baseTextSize
        originalTitleField.font = NSFont.systemFont(ofSize: baseTitleSize * scale, weight: .semibold)
        originalTextField.font = NSFont.systemFont(ofSize: baseTextSize * scale, weight: .medium)
        for section in layoutSections {
            section.titleField.font = NSFont.systemFont(ofSize: baseTitleSize * scale, weight: .semibold)
            section.textField.font = NSFont.systemFont(ofSize: baseTextSize * scale, weight: .medium)
        }
        loadingTextField.font = NSFont.systemFont(ofSize: baseLoadingSize * scale, weight: .regular)

        if window.isVisible, let location = lastAnchorLocation {
            let contentSize = layoutContent(showLoading: isShowingLoading, near: location)
            setWindowFrame(contentSize: contentSize, near: location, animated: false)
        }
    }

    func applyStrings() {
        originalTitleField.stringValue = UIStrings.Popup.originalTitle
        for section in layoutSections where section.isTranslation {
            section.titleField.stringValue = UIStrings.Popup.translationTitle
        }
        copyTranslationButton.tooltipText = UIStrings.Popup.copyTranslation
        copyAllButton.tooltipText = UIStrings.Popup.copyAll
        preferencesButton.tooltipText = UIStrings.Popup.openPreferences
        if isShowingLoading {
            updateLoadingText()
        }
    }

    func refreshLayout() {
        guard window.isVisible, let location = lastAnchorLocation else {
            return
        }
        let contentSize = layoutContent(showLoading: isShowingLoading, near: location)
        setWindowFrame(contentSize: contentSize, near: location, animated: false)
    }

    private func configureLayoutSections(_ layouts: [PopupLayoutDefinition]) {
        for section in layoutSections {
            section.dividerView.removeFromSuperview()
            section.titleField.removeFromSuperview()
            section.textField.removeFromSuperview()
        }
        layoutSections.removeAll(keepingCapacity: true)

        let scale = PopupFontPreferences.load() / baseTextSize
        for layout in layouts {
            let titleField = NSTextField(labelWithString: layout.title)
            titleField.font = NSFont.systemFont(ofSize: baseTitleSize * scale, weight: .semibold)
            titleField.textColor = .secondaryLabelColor
            titleField.backgroundColor = .clear
            titleField.isEditable = false
            titleField.isSelectable = false

            let textField = NSTextField(labelWithString: "")
            textField.font = NSFont.systemFont(ofSize: baseTextSize * scale, weight: .medium)
            textField.textColor = .labelColor
            textField.backgroundColor = .clear
            textField.isEditable = false
            textField.isSelectable = false
            textField.lineBreakMode = .byWordWrapping
            textField.maximumNumberOfLines = 0
            textField.cell?.wraps = true
            textField.cell?.usesSingleLineMode = false

            let dividerView = NSView()
            dividerView.wantsLayer = true
            dividerView.layer?.backgroundColor = NSColor.separatorColor.cgColor

            documentView.addSubview(dividerView)
            documentView.addSubview(titleField)
            documentView.addSubview(textField)
            layoutSections.append(LayoutSection(
                id: layout.id,
                titleField: titleField,
                textField: textField,
                dividerView: dividerView,
                isTranslation: layout.isTranslation
            ))
        }
    }

    private func layoutContent(showLoading: Bool, near location: CGPoint?) -> CGSize {
        loadingTextField.isHidden = !showLoading

        let previousScrollOrigin = scrollView.contentView.bounds.origin

        let padding = CGSize(width: 10, height: 8)
        let minWidth: CGFloat = 120
        let baseMaxWidth: CGFloat = 320
        let controlsHeight: CGFloat = 18
        let controlsSpacing: CGFloat = 6
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

        struct SectionSizes {
            let titleSize: CGSize
            let textSize: CGSize
        }

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

        func measureLayout(maxWidth: CGFloat, paddingRight: CGFloat) -> (contentWidth: CGFloat, contentHeight: CGFloat, sizes: (CGSize, CGSize, CGSize, [SectionSizes])) {
            let originalTitleSize = (originalTitleField.stringValue as NSString).size(withAttributes: titleAttributes)
            let textMaxWidth = maxWidth - paddingLeft - paddingRight
            let originalTextSize = textSize(for: originalTextField, maxWidth: textMaxWidth)
            let loadingTextSize = textSize(for: loadingTextField, maxWidth: textMaxWidth)

            var sectionSizes: [SectionSizes] = []
            sectionSizes.reserveCapacity(layoutSections.count)
            var contentTextWidth = max(originalTitleSize.width, originalTextSize.width, showLoading ? loadingTextSize.width : 0)
            for section in layoutSections {
                let titleSize = (section.titleField.stringValue as NSString).size(withAttributes: titleAttributes)
                let textSizeValue = textSize(for: section.textField, maxWidth: textMaxWidth)
                sectionSizes.append(SectionSizes(titleSize: titleSize, textSize: textSizeValue))
                contentTextWidth = max(contentTextWidth, max(titleSize.width, textSizeValue.width))
            }

            let contentWidth = max(minWidth, min(maxWidth, contentTextWidth + paddingLeft + paddingRight))
            let adjustedTextMaxWidth = contentWidth - paddingLeft - paddingRight
            if abs(adjustedTextMaxWidth - textMaxWidth) > 0.5 {
                let adjustedOriginalTextSize = textSize(for: originalTextField, maxWidth: adjustedTextMaxWidth)
                let adjustedLoadingTextSize = textSize(for: loadingTextField, maxWidth: adjustedTextMaxWidth)
                let adjustedSectionSizes = layoutSections.map { section in
                    SectionSizes(
                        titleSize: (section.titleField.stringValue as NSString).size(withAttributes: titleAttributes),
                        textSize: textSize(for: section.textField, maxWidth: adjustedTextMaxWidth)
                    )
                }
                return (
                    contentWidth,
                    contentHeight(
                        originalTitleSize: originalTitleSize,
                        originalTextSize: adjustedOriginalTextSize,
                        loadingTextSize: adjustedLoadingTextSize,
                        sectionSizes: adjustedSectionSizes,
                        titleTextSpacing: titleTextSpacing,
                        dividerHeight: dividerHeight,
                        dividerSpacing: dividerSpacing,
                        loadingSpacing: loadingSpacing,
                        padding: padding,
                        showLoading: showLoading
                    ),
                    (originalTitleSize, adjustedOriginalTextSize, adjustedLoadingTextSize, adjustedSectionSizes)
                )
            }

            let height = contentHeight(
                originalTitleSize: originalTitleSize,
                originalTextSize: originalTextSize,
                loadingTextSize: loadingTextSize,
                sectionSizes: sectionSizes,
                titleTextSpacing: titleTextSpacing,
                dividerHeight: dividerHeight,
                dividerSpacing: dividerSpacing,
                loadingSpacing: loadingSpacing,
                padding: padding,
                showLoading: showLoading
            )
            return (contentWidth, height, (originalTitleSize, originalTextSize, loadingTextSize, sectionSizes))
        }

        func contentHeight(
            originalTitleSize: CGSize,
            originalTextSize: CGSize,
            loadingTextSize: CGSize,
            sectionSizes: [SectionSizes],
            titleTextSpacing: CGFloat,
            dividerHeight: CGFloat,
            dividerSpacing: CGFloat,
            loadingSpacing: CGFloat,
            padding: CGSize,
            showLoading: Bool
        ) -> CGFloat {
            let originalTitleHeight = ceil(originalTitleSize.height)
            let originalTextHeight = max(ceil(originalTextSize.height), 16)
            let loadingTextHeight = max(ceil(loadingTextSize.height), 14)
            var height = padding.height * 2 + 4
                + originalTitleHeight
                + titleTextSpacing
                + originalTextHeight
            if showLoading {
                height += loadingSpacing + loadingTextHeight
            }
            for section in sectionSizes {
                let sectionTitleHeight = ceil(section.titleSize.height)
                let sectionTextHeight = max(ceil(section.textSize.height), 16)
                height += dividerSpacing
                    + dividerHeight
                    + dividerSpacing
                    + sectionTitleHeight
                    + titleTextSpacing
                    + sectionTextHeight
            }
            return height
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
        let originalTextSize = measurement.sizes.1
        let loadingTextSize = measurement.sizes.2
        let sectionSizes = measurement.sizes.3
        let contentHeight = measurement.contentHeight
        let visibleHeight = min(contentHeight, maxHeightLimit)

        let titleX = paddingLeft
        let textX = paddingLeft
        let availableWidth = contentWidth - paddingLeft - paddingRight
        originalTextField.preferredMaxLayoutWidth = availableWidth
        for section in layoutSections {
            section.textField.preferredMaxLayoutWidth = availableWidth
        }

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

        for (index, section) in layoutSections.enumerated() {
            let sizes = sectionSizes[index]
            y -= dividerSpacing + dividerHeight
            section.dividerView.frame = NSRect(
                x: paddingLeft,
                y: y,
                width: availableWidth,
                height: dividerHeight
            )
            y -= dividerSpacing + ceil(sizes.titleSize.height)
            section.titleField.frame = NSRect(
                x: titleX,
                y: y,
                width: availableWidth,
                height: ceil(sizes.titleSize.height)
            )
            y -= titleTextSpacing + max(ceil(sizes.textSize.height), 16)
            section.textField.frame = NSRect(
                x: textX,
                y: y,
                width: availableWidth,
                height: max(ceil(sizes.textSize.height), 16)
            )
        }

        let headerHeight = controlsHeight + controlsSpacing
        documentView.frame = NSRect(origin: .zero, size: CGSize(width: contentWidth, height: contentHeight))
        contentView.frame = NSRect(origin: .zero, size: CGSize(width: contentWidth, height: visibleHeight + headerHeight))
        scrollView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: visibleHeight)
        headerView.frame = NSRect(x: 0, y: visibleHeight, width: contentWidth, height: headerHeight)
        scrollView.hasVerticalScroller = needsVerticalScroll
        let maxScrollY = max(0, contentHeight - visibleHeight)
        let bottomY = scrollView.contentView.isFlipped ? maxScrollY : 0
        scrollView.contentView.scroll(to: NSPoint(x: previousScrollOrigin.x, y: bottomY))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        let buttonSize: CGFloat = 18
        let buttonSpacing: CGFloat = 6
        let buttonsWidth = CGFloat(actionButtons.count) * buttonSize + CGFloat(max(0, actionButtons.count - 1)) * buttonSpacing
        let buttonsX = max(paddingLeft, contentWidth - padding.width - buttonsWidth)
        let buttonsY = (headerHeight - buttonSize) * 0.5
        for (index, button) in actionButtons.enumerated() {
            let x = buttonsX + CGFloat(index) * (buttonSize + buttonSpacing)
            button.frame = NSRect(x: x, y: buttonsY, width: buttonSize, height: buttonSize)
        }
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
        loadingTextField.stringValue = UIStrings.Layout.loadingPrefix + dots
    }

    private func updateActionButtons() {
        let translationText = layoutSections.first(where: { $0.isTranslation })?.textField.stringValue ?? ""
        let hasTranslation = !translationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAnyResult = layoutSections.contains {
            !$0.textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        copyTranslationButton.isEnabled = hasTranslation
        copyAllButton.isEnabled = hasAnyResult
        let enabledAlpha: CGFloat = 1
        let disabledAlpha: CGFloat = 0.4
        copyTranslationButton.alphaValue = hasTranslation ? enabledAlpha : disabledAlpha
        copyAllButton.alphaValue = hasAnyResult ? enabledAlpha : disabledAlpha
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
        guard let window = button.window else {
            return
        }
        let rectInWindow = button.convert(button.bounds, to: nil)
        let rectOnScreen = window.convertToScreen(rectInWindow)
        let scale = PopupFontPreferences.load() / baseTextSize
        let fontSize = baseTooltipSize * scale
        tooltipWindow.show(text: button.tooltipText, near: rectOnScreen, fontSize: fontSize)
    }

    private func hideTooltip() {
        tooltipTimer?.invalidate()
        tooltipTimer = nil
        hoveredButton = nil
        tooltipWindow.hide()
    }

    @objc private func handleCopyTranslation() {
        hideTooltip()
        let text = layoutSections.first(where: { $0.isTranslation })?.textField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        copyToPasteboard(text)
    }

    @objc private func handleCopyAll() {
        hideTooltip()
        let original = originalTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let nonEmptySections = layoutSections.filter {
            !$0.textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if nonEmptySections.count == 1, nonEmptySections.first?.isTranslation == true {
            let translation = nonEmptySections.first?.textField.stringValue
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let combined = translation.isEmpty ? original : "\(original)\n\n\(translation)"
            copyToPasteboard(combined)
            return
        }
        var parts: [String] = []
        if !original.isEmpty {
            parts.append(original)
        }
        for section in nonEmptySections {
            let title = section.titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = section.textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                continue
            }
            if title.isEmpty {
                parts.append(text)
            } else {
                parts.append("\(title)\n\(text)")
            }
        }
        copyToPasteboard(parts.joined(separator: "\n\n"))
    }

    @objc private func handleOpenPreferences() {
        hideTooltip()
        onOpenPreferences?()
    }

    private func copyToPasteboard(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(trimmed, forType: .string)
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
