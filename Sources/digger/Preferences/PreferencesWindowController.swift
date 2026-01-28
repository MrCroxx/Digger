import AppKit
import Foundation

@MainActor
final class PreferencesWindowController: NSObject {
    private enum PreferencesTab: Int, CaseIterable {
        case general
        case popup
        case functions
        case advanced
        case api
    }

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
    private let popupShortcutLabelField: NSTextField
    private let popupShortcutField: ShortcutRecorderField
    private let languageLabelField: NSTextField
    private let targetLanguageLabelField: NSTextField
    private let languagePopUp: NSPopUpButton
    private let targetLanguagePopUp: NSPopUpButton
    private let popupFontSizeSlider: NSSlider
    private let popupFontSizeValueField: NSTextField
    private let streamingToggle: NSButton
    private let customFunctionsTitleField: NSTextField
    private let customFunctionsDescriptionField: NSTextField
    private let addFunctionButton: NSButton
    private let removeFunctionButton: NSButton
    private let customFunctionsTableView: NSTableView
    private let customFunctionsTableScrollView: NSScrollView
    private let tabView: NSTabView
    private let onPopupFontSizeChange: (CGFloat) -> Void
    private let onPopupLayoutChange: () -> Void
    private let onLanguageChange: () -> Void
    private let onForceClickSettingsChange: (Float, Float, TimeInterval) -> Void
    private let onCustomFunctionsChange: () -> Void
    nonisolated(unsafe) private var mouseDownMonitor: Any?

    init(
        onPopupFontSizeChange: @escaping (CGFloat) -> Void,
        onPopupLayoutChange: @escaping () -> Void,
        onLanguageChange: @escaping () -> Void,
        onForceClickSettingsChange: @escaping (Float, Float, TimeInterval) -> Void,
        onCustomFunctionsChange: @escaping () -> Void
    ) {
        AppPreferences.clearCustomFunctionsOnceIfNeeded()
        self.onPopupFontSizeChange = onPopupFontSizeChange
        self.onPopupLayoutChange = onPopupLayoutChange
        self.onLanguageChange = onLanguageChange
        self.onForceClickSettingsChange = onForceClickSettingsChange
        self.onCustomFunctionsChange = onCustomFunctionsChange
        NSApplication.shared.activate(ignoringOtherApps: true)
        let contentView = NSView()
        contentView.wantsLayer = true

        titleField = NSTextField(labelWithString: UIStrings.Preferences.title)
        titleField.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        titleField.textColor = .labelColor

        descriptionField = NSTextField(wrappingLabelWithString: UIStrings.Preferences.description)
        descriptionField.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        descriptionField.textColor = .secondaryLabelColor

        apiKeyField = NSSecureTextField()
        apiKeyField.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        apiKeyField.controlSize = .small
        apiKeyField.placeholderString = "sk-..."
        apiKeyField.isEditable = true
        apiKeyField.isSelectable = true
        apiKeyField.isBordered = true
        apiKeyField.focusRingType = .default
        endpointField = NSTextField()
        endpointField.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        endpointField.controlSize = .small
        endpointField.placeholderString = "https://api.openai.com/v1"
        endpointField.isEditable = true
        endpointField.isSelectable = true
        thresholdField = NSTextField()
        thresholdField.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        thresholdField.controlSize = .small
        thresholdField.isEditable = true
        thresholdField.isSelectable = true
        deltaField = NSTextField()
        deltaField.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        deltaField.controlSize = .small
        deltaField.isEditable = true
        deltaField.isSelectable = true
        windowField = NSTextField()
        windowField.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        windowField.controlSize = .small
        windowField.isEditable = true
        windowField.isSelectable = true
        popupMaxWidthField = NSTextField()
        popupMaxWidthField.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        popupMaxWidthField.controlSize = .small
        popupMaxWidthField.isEditable = true
        popupMaxWidthField.isSelectable = true
        popupMaxHeightField = NSTextField()
        popupMaxHeightField.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        popupMaxHeightField.controlSize = .small
        popupMaxHeightField.isEditable = true
        popupMaxHeightField.isSelectable = true
        popupTooltipDelayField = NSTextField()
        popupTooltipDelayField.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        popupTooltipDelayField.controlSize = .small
        popupTooltipDelayField.isEditable = true
        popupTooltipDelayField.isSelectable = true
        popupFontSizeLabelField = NSTextField(labelWithString: UIStrings.Preferences.popupFontSizeLabel)
        popupFontSizeLabelField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        popupFontSizeLabelField.textColor = .secondaryLabelColor
        popupTooltipDelayLabelField = NSTextField(labelWithString: UIStrings.Preferences.popupTooltipDelayLabel)
        popupTooltipDelayLabelField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        popupTooltipDelayLabelField.textColor = .secondaryLabelColor
        popupShortcutLabelField = NSTextField(labelWithString: UIStrings.Preferences.popupShortcutLabel)
        popupShortcutLabelField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        popupShortcutLabelField.textColor = .secondaryLabelColor
        popupShortcutField = ShortcutRecorderField()
        popupShortcutField.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        popupShortcutField.controlSize = .small
        popupShortcutField.isEditable = true
        popupShortcutField.isSelectable = false
        popupShortcutField.isBordered = true
        popupShortcutField.focusRingType = .default
        popupShortcutField.placeholderString = UIStrings.Preferences.popupShortcutPlaceholder
        popupShortcutField.currentShortcut = AppPreferences.popupShortcut()
        popupShortcutField.onShortcutChange = { shortcut in
            AppPreferences.setPopupShortcut(shortcut)
        }
        languageLabelField = NSTextField(labelWithString: UIStrings.Preferences.languageLabel)
        languageLabelField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        languageLabelField.textColor = .secondaryLabelColor
        languagePopUp = NSPopUpButton()
        languagePopUp.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        languagePopUp.controlSize = .small
        languagePopUp.isBordered = true
        for (index, language) in AppLanguage.allCases.enumerated() {
            languagePopUp.addItem(withTitle: language.displayName)
            languagePopUp.item(at: index)?.representedObject = language.rawValue
        }
        targetLanguageLabelField = NSTextField(labelWithString: UIStrings.Preferences.targetLanguageLabel)
        targetLanguageLabelField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        targetLanguageLabelField.textColor = .secondaryLabelColor
        targetLanguagePopUp = NSPopUpButton()
        targetLanguagePopUp.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        targetLanguagePopUp.controlSize = .small
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
        popupFontSizeSlider.controlSize = .small
        popupFontSizeValueField = PreferencesWindowController.makeValueField()
        popupFontSizeValueField.alignment = .right
        popupFontSizeValueField.stringValue = PopupFontPreferences.format(PopupFontPreferences.load())

        streamingToggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        streamingToggle.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        streamingToggle.controlSize = .small

        customFunctionsTitleField = NSTextField(labelWithString: UIStrings.Preferences.customFunctionsTitle)
        customFunctionsTitleField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        customFunctionsTitleField.textColor = .labelColor
        customFunctionsDescriptionField = NSTextField(wrappingLabelWithString: UIStrings.Preferences.customFunctionsDescription)
        customFunctionsDescriptionField.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        customFunctionsDescriptionField.textColor = .secondaryLabelColor
        addFunctionButton = NSButton(title: "+", target: nil, action: nil)
        addFunctionButton.bezelStyle = .texturedRounded
        addFunctionButton.controlSize = .small
        removeFunctionButton = NSButton(title: "-", target: nil, action: nil)
        removeFunctionButton.bezelStyle = .texturedRounded
        removeFunctionButton.controlSize = .small
        removeFunctionButton.isEnabled = false

        customFunctionsTableView = NSTableView()
        customFunctionsTableView.allowsMultipleSelection = false
        customFunctionsTableView.allowsColumnSelection = false
        customFunctionsTableView.headerView = nil
        customFunctionsTableView.usesAlternatingRowBackgroundColors = false
        customFunctionsTableView.rowSizeStyle = .medium

        let titleColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        titleColumn.title = UIStrings.Preferences.functionTitleLabel
        titleColumn.resizingMask = .userResizingMask
        titleColumn.minWidth = 120
        titleColumn.width = 160

        let promptColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("prompt"))
        promptColumn.title = UIStrings.Preferences.functionPromptLabel
        promptColumn.resizingMask = .autoresizingMask
        promptColumn.minWidth = 220

        customFunctionsTableView.addTableColumn(titleColumn)
        customFunctionsTableView.addTableColumn(promptColumn)

        customFunctionsTableScrollView = NSScrollView()
        customFunctionsTableScrollView.drawsBackground = true
        customFunctionsTableScrollView.hasVerticalScroller = true
        customFunctionsTableScrollView.hasHorizontalScroller = false
        customFunctionsTableScrollView.autohidesScrollers = true
        customFunctionsTableScrollView.borderType = .noBorder
        customFunctionsTableScrollView.translatesAutoresizingMaskIntoConstraints = false
        customFunctionsTableScrollView.documentView = customFunctionsTableView
        customFunctionsTableScrollView.wantsLayer = true
        customFunctionsTableScrollView.layer?.cornerRadius = 8
        customFunctionsTableScrollView.layer?.masksToBounds = true
        customFunctionsTableScrollView.backgroundColor = .controlBackgroundColor
        customFunctionsTableView.backgroundColor = .clear

        tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false

        let customFunctionsHeader = NSStackView(views: [customFunctionsTitleField, NSView(), addFunctionButton, removeFunctionButton])
        customFunctionsHeader.orientation = .horizontal
        customFunctionsHeader.alignment = .centerY
        customFunctionsHeader.spacing = 8
        customFunctionsTitleField.setContentHuggingPriority(.required, for: .horizontal)
        addFunctionButton.setContentHuggingPriority(.required, for: .horizontal)
        removeFunctionButton.setContentHuggingPriority(.required, for: .horizontal)

        let generalStackView = Self.makeContentStackView()
        generalStackView.addArrangedSubview(titleField)
        generalStackView.addArrangedSubview(descriptionField)
        generalStackView.addArrangedSubview(Self.makeRow(labelField: languageLabelField, field: languagePopUp))
        generalStackView.addArrangedSubview(Self.makeRow(labelField: targetLanguageLabelField, field: targetLanguagePopUp))
        generalStackView.addArrangedSubview(streamingToggle)

        let popupStackView = Self.makeContentStackView()
        popupStackView.addArrangedSubview(Self.makeSliderRow(
            labelField: popupFontSizeLabelField,
            slider: popupFontSizeSlider,
            valueField: popupFontSizeValueField
        ))
        popupStackView.addArrangedSubview(Self.makeRow(labelField: popupTooltipDelayLabelField, field: popupTooltipDelayField))
        popupStackView.addArrangedSubview(Self.makeRow(labelField: popupShortcutLabelField, field: popupShortcutField))
        popupStackView.addArrangedSubview(Self.makeEditRow(label: "POPUP_MAX_WIDTH", field: popupMaxWidthField))
        popupStackView.addArrangedSubview(Self.makeEditRow(label: "POPUP_MAX_HEIGHT", field: popupMaxHeightField))

        let functionsStackView = Self.makeContentStackView()
        functionsStackView.addArrangedSubview(customFunctionsHeader)
        functionsStackView.addArrangedSubview(customFunctionsDescriptionField)
        functionsStackView.addArrangedSubview(customFunctionsTableScrollView)

        let advancedStackView = Self.makeContentStackView()
        advancedStackView.addArrangedSubview(Self.makeEditRow(label: "FORCE_CLICK_PRESSURE_THRESHOLD", field: thresholdField))
        advancedStackView.addArrangedSubview(Self.makeEditRow(label: "FORCE_CLICK_PRESSURE_DELTA", field: deltaField))
        advancedStackView.addArrangedSubview(Self.makeEditRow(label: "FORCE_CLICK_BASELINE_WINDOW_MS", field: windowField))

        let apiStackView = Self.makeContentStackView()
        apiStackView.addArrangedSubview(Self.makeEditRow(label: "OPENAI_API_KEY", field: apiKeyField))
        apiStackView.addArrangedSubview(Self.makeEditRow(label: "OPENAI_ENDPOINT", field: endpointField))

        customFunctionsTableScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = UIStrings.Preferences.title
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = contentView
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true

        super.init()
        configureTabs(
            in: contentView,
            generalStackView: generalStackView,
            popupStackView: popupStackView,
            functionsStackView: functionsStackView,
            advancedStackView: advancedStackView,
            apiStackView: apiStackView
        )
        selectTab(.general)
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
        addFunctionButton.target = self
        addFunctionButton.action = #selector(handleAddFunction(_:))
        removeFunctionButton.target = self
        removeFunctionButton.action = #selector(handleRemoveFunction(_:))

        customFunctionsTableView.dataSource = self
        customFunctionsTableView.delegate = self

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
        window.makeFirstResponder(languagePopUp)
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
        popupShortcutField.currentShortcut = AppPreferences.popupShortcut()
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
        for item in tabView.tabViewItems {
            guard let tab = item.identifier as? PreferencesTab else {
                continue
            }
            item.label = tabTitle(for: tab)
            item.image = tabIcon(for: tab)
        }
        popupFontSizeLabelField.stringValue = UIStrings.Preferences.popupFontSizeLabel
        popupTooltipDelayLabelField.stringValue = UIStrings.Preferences.popupTooltipDelayLabel
        popupShortcutLabelField.stringValue = UIStrings.Preferences.popupShortcutLabel
        popupShortcutField.placeholderString = UIStrings.Preferences.popupShortcutPlaceholder
        languageLabelField.stringValue = UIStrings.Preferences.languageLabel
        targetLanguageLabelField.stringValue = UIStrings.Preferences.targetLanguageLabel
        streamingToggle.title = UIStrings.Preferences.streamingLabel
        customFunctionsTitleField.stringValue = UIStrings.Preferences.customFunctionsTitle
        customFunctionsDescriptionField.stringValue = UIStrings.Preferences.customFunctionsDescription
        addFunctionButton.title = "+"
        removeFunctionButton.title = "-"
        for column in customFunctionsTableView.tableColumns {
            if column.identifier.rawValue == "title" {
                column.title = UIStrings.Preferences.functionTitleLabel
            } else if column.identifier.rawValue == "prompt" {
                column.title = UIStrings.Preferences.functionPromptLabel
            }
        }
        window.title = UIStrings.Preferences.title
        reloadCustomFunctions()
    }

    private func tabTitle(for tab: PreferencesTab) -> String {
        switch tab {
        case .general:
            return UIStrings.Preferences.tabGeneral
        case .popup:
            return UIStrings.Preferences.tabPopup
        case .functions:
            return UIStrings.Preferences.tabFunctions
        case .advanced:
            return UIStrings.Preferences.tabAdvanced
        case .api:
            return UIStrings.Preferences.tabAPI
        }
    }

    private func selectTab(_ tab: PreferencesTab) {
        if tab.rawValue < tabView.numberOfTabViewItems {
            let item = tabView.tabViewItem(at: tab.rawValue)
            tabView.selectTabViewItem(item)
        }
    }

    private func configureTabs(
        in contentView: NSView,
        generalStackView: NSStackView,
        popupStackView: NSStackView,
        functionsStackView: NSStackView,
        advancedStackView: NSStackView,
        apiStackView: NSStackView
    ) {
        tabView.addTabViewItem(makeTabViewItem(for: .general, contentView: makeTabContentView(generalStackView)))
        tabView.addTabViewItem(makeTabViewItem(for: .popup, contentView: makeTabContentView(popupStackView)))
        tabView.addTabViewItem(makeTabViewItem(for: .functions, contentView: makeTabContentView(functionsStackView)))
        tabView.addTabViewItem(makeTabViewItem(for: .advanced, contentView: makeTabContentView(advancedStackView)))
        tabView.addTabViewItem(makeTabViewItem(for: .api, contentView: makeTabContentView(apiStackView)))
        contentView.addSubview(tabView)

        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tabView.topAnchor.constraint(equalTo: contentView.topAnchor),
            tabView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    private func makeTabViewItem(for tab: PreferencesTab, contentView: NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: tab)
        item.label = tabTitle(for: tab)
        item.image = tabIcon(for: tab)
        item.view = contentView
        return item
    }

    private static func makeContentStackView() -> NSStackView {
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 14
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        return stackView
    }

    private func makeTabContentView(_ stackView: NSStackView) -> NSView {
        let container = NSView()
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stackView

        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])

        return container
    }


    private func tabIcon(for tab: PreferencesTab) -> NSImage? {
        let name: String
        switch tab {
        case .general:
            name = "gearshape"
        case .popup:
            name = "rectangle.on.rectangle"
        case .functions:
            name = "function"
        case .advanced:
            name = "slider.horizontal.3"
        case .api:
            name = "key"
        }
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }

    private static func makeValueField() -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        field.textColor = .labelColor
        field.lineBreakMode = .byTruncatingMiddle
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    private static func makeRow(label: String, valueField: NSTextField) -> NSStackView {
        let labelField = NSTextField(labelWithString: label)
        labelField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
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
        labelField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
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

    private func reloadCustomFunctions(_ functionsOverride: [CustomFunction]? = nil) {
        let functions = functionsOverride ?? AppPreferences.customFunctions()
        removeFunctionButton.isEnabled = customFunctionsTableView.selectedRow >= 0
        customFunctionsTableView.reloadData()
        if !functions.isEmpty, customFunctionsTableView.selectedRow == -1 {
            customFunctionsTableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }


    @objc private func handleAddFunction(_ sender: Any?) {
        print("[Preferences] Add Function clicked")
        var functions = AppPreferences.customFunctions()
        let newFunction = CustomFunction(title: UIStrings.Preferences.functionDefaultTitle, prompt: "")
        functions.append(newFunction)
        AppPreferences.setCustomFunctions(functions)
        reloadCustomFunctions(functions)
        let newRow = max(0, functions.count - 1)
        customFunctionsTableView.selectRowIndexes(IndexSet(integer: newRow), byExtendingSelection: false)
        customFunctionsTableView.scrollRowToVisible(newRow)
        onCustomFunctionsChange()
    }

    @objc private func handleRemoveFunction(_ sender: Any?) {
        let selectedRow = customFunctionsTableView.selectedRow
        guard selectedRow >= 0 else {
            return
        }
        var functions = AppPreferences.customFunctions()
        if selectedRow < functions.count {
            functions.remove(at: selectedRow)
        }
        AppPreferences.setCustomFunctions(functions)
        reloadCustomFunctions(functions)
        onCustomFunctionsChange()
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
        if customFunctionsTableView.row(for: field) != -1 {
            let row = customFunctionsTableView.row(for: field)
            let column = customFunctionsTableView.column(for: field)
            let functions = AppPreferences.customFunctions()
            guard row >= 0, row < functions.count else {
                return
            }
            var updated = functions[row]
            if column == 0 {
                updated.title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                updated.prompt = field.stringValue
            }
            var newFunctions = functions
            newFunctions[row] = updated
            AppPreferences.setCustomFunctions(newFunctions)
            onCustomFunctionsChange()
            if shouldResignFocusOnEndEditing(obj) {
                window.makeFirstResponder(nil)
            }
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

extension PreferencesWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        AppPreferences.customFunctions().count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let functions = AppPreferences.customFunctions()
        guard row >= 0, row < functions.count, let tableColumn else {
            return nil
        }

        let identifier = tableColumn.identifier
        let cellIdentifier = NSUserInterfaceItemIdentifier("CustomFunctionCell_\(identifier.rawValue)")
        let cellView: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView {
            cellView = reused
        } else {
            cellView = NSTableCellView()
            cellView.identifier = cellIdentifier
            let textField = NSTextField()
            textField.isEditable = true
            textField.isSelectable = true
            textField.isBordered = true
            textField.font = NSFont.systemFont(ofSize: 13, weight: .regular)
            textField.controlSize = .small
            textField.delegate = self
            textField.translatesAutoresizingMaskIntoConstraints = false
            cellView.addSubview(textField)
            cellView.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
            ])
        }

        if let textField = cellView.textField {
            if identifier.rawValue == "title" {
                textField.placeholderString = UIStrings.Preferences.functionTitlePlaceholder
                textField.stringValue = functions[row].title
            } else {
                textField.placeholderString = UIStrings.Preferences.functionPromptPlaceholder
                textField.stringValue = functions[row].prompt
            }
        }
        return cellView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        removeFunctionButton.isEnabled = customFunctionsTableView.selectedRow >= 0
    }
}
