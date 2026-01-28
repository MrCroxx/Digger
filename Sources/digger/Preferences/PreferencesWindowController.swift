import AppKit
import Foundation

@MainActor
final class PreferencesWindowController: NSObject {
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
    private let popupTooltipDelayField: NSTextField
    private let popupFontSizeLabelField: NSTextField
    private let popupTooltipDelayLabelField: NSTextField
    private let languageLabelField: NSTextField
    private let targetLanguageLabelField: NSTextField
    private let languagePopUp: NSPopUpButton
    private let targetLanguagePopUp: NSPopUpButton
    private let popupFontSizeSlider: NSSlider
    private let popupFontSizeValueField: NSTextField
    private let streamingToggle: NSButton
    private let onPopupFontSizeChange: (CGFloat) -> Void
    private let onPopupLayoutChange: () -> Void
    private let onLanguageChange: () -> Void
    private let onForceClickSettingsChange: (Float, Float, TimeInterval) -> Void
    nonisolated(unsafe) private var mouseDownMonitor: Any?

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
        popupTooltipDelayField = NSTextField()
        popupTooltipDelayField.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        popupTooltipDelayField.isEditable = true
        popupTooltipDelayField.isSelectable = true
        popupFontSizeLabelField = NSTextField(labelWithString: UIStrings.Preferences.popupFontSizeLabel)
        popupFontSizeLabelField.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        popupFontSizeLabelField.textColor = .secondaryLabelColor
        popupTooltipDelayLabelField = NSTextField(labelWithString: UIStrings.Preferences.popupTooltipDelayLabel)
        popupTooltipDelayLabelField.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        popupTooltipDelayLabelField.textColor = .secondaryLabelColor
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
        targetLanguageLabelField = NSTextField(labelWithString: UIStrings.Preferences.targetLanguageLabel)
        targetLanguageLabelField.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        targetLanguageLabelField.textColor = .secondaryLabelColor
        targetLanguagePopUp = NSPopUpButton()
        targetLanguagePopUp.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        targetLanguagePopUp.isBordered = true
        for (index, language) in TranslationTargetLanguage.allCases.enumerated() {
            targetLanguagePopUp.addItem(withTitle: language.displayName)
            targetLanguagePopUp.item(at: index)?.representedObject = language.rawValue
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

        streamingToggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        streamingToggle.font = NSFont.systemFont(ofSize: 12, weight: .regular)

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
        stackView.addArrangedSubview(Self.makeRow(labelField: popupTooltipDelayLabelField, field: popupTooltipDelayField))
        stackView.addArrangedSubview(Self.makeRow(labelField: languageLabelField, field: languagePopUp))
        stackView.addArrangedSubview(Self.makeRow(labelField: targetLanguageLabelField, field: targetLanguagePopUp))
        stackView.addArrangedSubview(streamingToggle)
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
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 330),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = UIStrings.Preferences.title
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = contentView

        super.init()
        let backgroundClickRecognizer = NSClickGestureRecognizer(target: self, action: #selector(handleBackgroundClick(_:)))
        contentView.addGestureRecognizer(backgroundClickRecognizer)
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
        popupTooltipDelayField.target = self
        popupTooltipDelayField.action = #selector(handlePopupTooltipDelayChange(_:))
        languagePopUp.target = self
        languagePopUp.action = #selector(handleLanguageChange(_:))
        targetLanguagePopUp.target = self
        targetLanguagePopUp.action = #selector(handleTargetLanguageChange(_:))
        streamingToggle.target = self
        streamingToggle.action = #selector(handleStreamingToggle(_:))

        apiKeyField.delegate = self
        endpointField.delegate = self
        thresholdField.delegate = self
        deltaField.delegate = self
        windowField.delegate = self
        popupMaxWidthField.delegate = self
        popupMaxHeightField.delegate = self
        popupTooltipDelayField.delegate = self
        refreshValues()

        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self, event.window == self.window else {
                return event
            }
            self.resignFocusIfNeeded(for: event)
            return event
        }
    }

    deinit {
        if let mouseDownMonitor {
            NSEvent.removeMonitor(mouseDownMonitor)
        }
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
        popupTooltipDelayField.stringValue = String(format: "%.0f", AppPreferences.popupTooltipDelayMs())
        streamingToggle.state = AppPreferences.translationStreamingEnabled() ? .on : .off
        if let index = AppLanguage.allCases.firstIndex(of: AppPreferences.language()) {
            languagePopUp.selectItem(at: index)
        }
        if let index = TranslationTargetLanguage.allCases.firstIndex(of: AppPreferences.translationTargetLanguage()) {
            targetLanguagePopUp.selectItem(at: index)
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
        popupTooltipDelayLabelField.stringValue = UIStrings.Preferences.popupTooltipDelayLabel
        languageLabelField.stringValue = UIStrings.Preferences.languageLabel
        targetLanguageLabelField.stringValue = UIStrings.Preferences.targetLanguageLabel
        streamingToggle.title = UIStrings.Preferences.streamingLabel
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

    @objc private func handlePopupTooltipDelayChange(_ sender: NSTextField) {
        if let value = Double(sender.stringValue) {
            AppPreferences.setPopupTooltipDelayMs(CGFloat(value))
        }
        sender.stringValue = String(format: "%.0f", AppPreferences.popupTooltipDelayMs())
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

    @objc private func handleTargetLanguageChange(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let language = TranslationTargetLanguage(rawValue: rawValue) else {
            return
        }
        AppPreferences.setTranslationTargetLanguage(language)
    }

    @objc private func handleStreamingToggle(_ sender: NSButton) {
        AppPreferences.setTranslationStreamingEnabled(sender.state == .on)
    }


    private func notifyForceClickSettingsChange() {
        onForceClickSettingsChange(
            Float(AppPreferences.pressureThreshold()),
            Float(AppPreferences.pressureDelta()),
            TimeInterval(AppPreferences.baselineWindowMs() / 1000)
        )
    }

    @objc private func handleBackgroundClick(_ sender: NSClickGestureRecognizer) {
        guard let contentView = window.contentView else {
            return
        }
        let location = sender.location(in: contentView)
        let hitView = contentView.hitTest(location)
        if let hitView, editableTextField(from: hitView) != nil {
            return
        }
        if isEditingTextField() {
            window.makeFirstResponder(nil)
        }
    }

    private func shouldResignFocusOnEndEditing(_ notification: Notification) -> Bool {
        guard let movementValue = notification.userInfo?[NSText.movementUserInfoKey] as? Int else {
            return false
        }
        return movementValue == NSReturnTextMovement
    }

    private func editableTextField(from view: NSView) -> NSTextField? {
        var current: NSView? = view
        while let candidate = current {
            if let textField = candidate as? NSTextField, textField.isEditable {
                return textField
            }
            current = candidate.superview
        }
        return nil
    }

    private func isEditingTextField() -> Bool {
        if let textView = window.firstResponder as? NSTextView {
            return textView.isFieldEditor
        }
        if let textField = window.firstResponder as? NSTextField {
            return textField.isEditable
        }
        return false
    }

    private func resignFocusIfNeeded(for event: NSEvent) {
        guard let contentView = window.contentView else {
            return
        }
        let location = contentView.convert(event.locationInWindow, from: nil)
        let hitView = contentView.hitTest(location)
        if let hitView, editableTextField(from: hitView) != nil {
            return
        }
        if isEditingTextField() {
            window.makeFirstResponder(nil)
        }
    }
}

extension PreferencesWindowController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        return
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
        case popupTooltipDelayField:
            handlePopupTooltipDelayChange(field)
        case thresholdField:
            handleThresholdChange(field)
        case deltaField:
            handleDeltaChange(field)
        case windowField:
            handleWindowMsChange(field)
        default:
            break
        }
        if shouldResignFocusOnEndEditing(obj) {
            window.makeFirstResponder(nil)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            window.makeFirstResponder(nil)
            return true
        }
        return false
    }
}
