import AppKit
import SwiftUI

struct PreferencesView: View {
    private enum PreferencesTab: String, CaseIterable, Identifiable {
        case general
        case popup
        case functions
        case advanced
        case api

        var id: String { rawValue }

        var title: String {
            switch self {
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

        var systemImage: String {
            switch self {
            case .general:
                return "gearshape"
            case .popup:
                return "rectangle.on.rectangle"
            case .functions:
                return "function"
            case .advanced:
                return "slider.horizontal.3"
            case .api:
                return "key"
            }
        }
    }

    private enum Field: Hashable {
        case popupTooltipDelay
        case popupMaxWidth
        case popupMaxHeight
        case pressureThreshold
        case pressureDelta
        case baselineWindow
    }

    @ObservedObject var viewModel: PreferencesViewModel
    let onPopupFontSizeChange: (CGFloat) -> Void
    let onPopupLayoutChange: () -> Void
    let onLanguageChange: () -> Void
    let onForceClickSettingsChange: (Float, Float, TimeInterval) -> Void
    let onCustomFunctionsChange: () -> Void

    @State private var selection: PreferencesTab? = .general
    @FocusState private var focusedField: Field?
    @State private var lastFocusedField: Field?

    var body: some View {
        NavigationSplitView {
            List(PreferencesTab.allCases, selection: $selection) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 200)
        } detail: {
            detailView
        }
        .frame(minWidth: 720, minHeight: 460)
        .onChange(of: focusedField) { newValue in
            if let lastFocusedField, lastFocusedField != newValue {
                applyField(lastFocusedField)
            }
            lastFocusedField = newValue
        }
        .onChange(of: viewModel.language) { newValue in
            AppPreferences.setLanguage(newValue)
            onLanguageChange()
        }
        .onChange(of: viewModel.targetLanguage) { newValue in
            AppPreferences.setTranslationTargetLanguage(newValue)
        }
        .onChange(of: viewModel.streamingEnabled) { newValue in
            AppPreferences.setTranslationStreamingEnabled(newValue)
        }
        .onChange(of: viewModel.popupFontSize) { newValue in
            let clamped = Double(PopupFontPreferences.clamp(CGFloat(newValue)))
            if clamped != newValue {
                viewModel.popupFontSize = clamped
                return
            }
            PopupFontPreferences.save(CGFloat(clamped))
            onPopupFontSizeChange(CGFloat(clamped))
        }
        .onChange(of: viewModel.popupShortcut) { newValue in
            AppPreferences.setPopupShortcut(newValue)
        }
        .onChange(of: viewModel.apiKey) { newValue in
            AppPreferences.setApiKey(newValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        .onChange(of: viewModel.endpoint) { newValue in
            AppPreferences.setEndpoint(newValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        .onChange(of: viewModel.model) { newValue in
            AppPreferences.setModel(newValue)
        }
        .onChange(of: viewModel.systemPrompt) { newValue in
            AppPreferences.setSystemPrompt(newValue)
        }
        .onChange(of: viewModel.customFunctions) { newValue in
            AppPreferences.setCustomFunctions(newValue)
            onCustomFunctionsChange()
            if let selectedFunctionID = viewModel.selectedFunctionID,
               !newValue.contains(where: { $0.id == selectedFunctionID }) {
                viewModel.selectedFunctionID = newValue.first?.id
            }
        }
    }

    private var detailView: some View {
        Group {
            switch selection ?? .general {
            case .general:
                generalPane
            case .popup:
                popupPane
            case .functions:
                functionsPane
            case .advanced:
                advancedPane
            case .api:
                apiPane
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(UIStrings.Preferences.title)
                .font(.system(size: 18, weight: .semibold))
            Text(UIStrings.Preferences.description)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView
            Form {
                LabeledContent(UIStrings.Preferences.languageLabel) {
                    Picker("", selection: $viewModel.language) {
                        ForEach(AppLanguage.allCases, id: \.self) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }
                LabeledContent(UIStrings.Preferences.targetLanguageLabel) {
                    Picker("", selection: $viewModel.targetLanguage) {
                        ForEach(TranslationTargetLanguage.allCases, id: \.self) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }
                Toggle(UIStrings.Preferences.streamingLabel, isOn: $viewModel.streamingEnabled)
            }
        }
    }

    private var popupPane: some View {
        Form {
            LabeledContent(UIStrings.Preferences.popupFontSizeLabel) {
                HStack(spacing: 12) {
                    Slider(
                        value: $viewModel.popupFontSize,
                        in: Double(PopupFontPreferences.minSize)...Double(PopupFontPreferences.maxSize),
                        step: 1
                    )
                    Text(PopupFontPreferences.format(CGFloat(viewModel.popupFontSize)))
                        .foregroundColor(.secondary)
                        .frame(width: 54, alignment: .trailing)
                }
            }
            LabeledContent(UIStrings.Preferences.popupTooltipDelayLabel) {
                TextField("", text: $viewModel.popupTooltipDelayText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .focused($focusedField, equals: .popupTooltipDelay)
            }
            LabeledContent(UIStrings.Preferences.popupShortcutLabel) {
                ShortcutRecorderView(
                    shortcut: $viewModel.popupShortcut,
                    placeholder: UIStrings.Preferences.popupShortcutPlaceholder
                ) { newShortcut in
                    AppPreferences.setPopupShortcut(newShortcut)
                }
                .frame(width: 180)
            }
            LabeledContent("POPUP_MAX_WIDTH") {
                TextField("", text: $viewModel.popupMaxWidthText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .focused($focusedField, equals: .popupMaxWidth)
            }
            LabeledContent("POPUP_MAX_HEIGHT") {
                TextField("", text: $viewModel.popupMaxHeightText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .focused($focusedField, equals: .popupMaxHeight)
            }
        }
    }

    private var functionsPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(UIStrings.Preferences.systemPromptTitle)
                    .font(.system(size: 13, weight: .semibold))
                Text(UIStrings.Preferences.systemPromptDescription)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                TextField(
                    UIStrings.Preferences.systemPromptPlaceholder,
                    text: $viewModel.systemPrompt
                )
                .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(UIStrings.Preferences.customFunctionsTitle)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button("+") {
                        addFunction()
                    }
                    .frame(width: 24)
                }
                Text(UIStrings.Preferences.customFunctionsDescription)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                List(selection: $viewModel.selectedFunctionID) {
                    ForEach(viewModel.customFunctions.indices, id: \.self) { index in
                        HStack(spacing: 12) {
                            TextField(
                                UIStrings.Preferences.functionTitlePlaceholder,
                                text: $viewModel.customFunctions[index].title
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                            TextField(
                                UIStrings.Preferences.functionPromptPlaceholder,
                                text: $viewModel.customFunctions[index].prompt
                            )
                            .textFieldStyle(.roundedBorder)
                            Button("-") {
                                removeFunction(viewModel.customFunctions[index].id)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .frame(width: 24)
                        }
                        .tag(viewModel.customFunctions[index].id)
                    }
                }
                .frame(minHeight: 180)
            }
        }
    }

    private var advancedPane: some View {
        Form {
            LabeledContent("FORCE_CLICK_PRESSURE_THRESHOLD") {
                TextField("", text: $viewModel.pressureThresholdText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .focused($focusedField, equals: .pressureThreshold)
            }
            LabeledContent("FORCE_CLICK_PRESSURE_DELTA") {
                TextField("", text: $viewModel.pressureDeltaText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .focused($focusedField, equals: .pressureDelta)
            }
            LabeledContent("FORCE_CLICK_BASELINE_WINDOW_MS") {
                TextField("", text: $viewModel.baselineWindowText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .focused($focusedField, equals: .baselineWindow)
            }
        }
    }

    private var apiPane: some View {
        Form {
            LabeledContent("OPENAI_API_KEY") {
                SecureField("", text: $viewModel.apiKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
            }
            LabeledContent("OPENAI_ENDPOINT") {
                TextField("", text: $viewModel.endpoint)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
            }
            LabeledContent("OPENAI_MODEL") {
                TextField("", text: $viewModel.model)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
            }
        }
    }

    private func addFunction() {
        let newFunction = CustomFunction(title: UIStrings.Preferences.functionDefaultTitle, prompt: "")
        viewModel.customFunctions.append(newFunction)
        viewModel.selectedFunctionID = newFunction.id
    }

    private func removeFunction(_ id: UUID) {
        guard let index = viewModel.customFunctions.firstIndex(where: { $0.id == id }) else {
            return
        }
        let wasSelected = viewModel.selectedFunctionID == id
        viewModel.customFunctions.remove(at: index)
        if wasSelected {
            viewModel.selectedFunctionID = viewModel.customFunctions.first?.id
        }
    }

    private func applyField(_ field: Field) {
        switch field {
        case .popupTooltipDelay:
            applyPopupTooltipDelay()
        case .popupMaxWidth:
            applyPopupMaxWidth()
        case .popupMaxHeight:
            applyPopupMaxHeight()
        case .pressureThreshold:
            applyPressureThreshold()
        case .pressureDelta:
            applyPressureDelta()
        case .baselineWindow:
            applyBaselineWindow()
        }
    }

    private func applyPopupTooltipDelay() {
        guard let value = Double(viewModel.popupTooltipDelayText) else {
            viewModel.popupTooltipDelayText = String(format: "%.0f", AppPreferences.popupTooltipDelayMs())
            return
        }
        AppPreferences.setPopupTooltipDelayMs(CGFloat(value))
        viewModel.popupTooltipDelayText = String(format: "%.0f", AppPreferences.popupTooltipDelayMs())
    }

    private func applyPopupMaxWidth() {
        guard let value = Double(viewModel.popupMaxWidthText) else {
            viewModel.popupMaxWidthText = String(format: "%.0f", AppPreferences.popupMaxWidth())
            return
        }
        AppPreferences.setPopupMaxWidth(CGFloat(value))
        viewModel.popupMaxWidthText = String(format: "%.0f", AppPreferences.popupMaxWidth())
        onPopupLayoutChange()
    }

    private func applyPopupMaxHeight() {
        guard let value = Double(viewModel.popupMaxHeightText) else {
            viewModel.popupMaxHeightText = String(format: "%.0f", AppPreferences.popupMaxHeight())
            return
        }
        AppPreferences.setPopupMaxHeight(CGFloat(value))
        viewModel.popupMaxHeightText = String(format: "%.0f", AppPreferences.popupMaxHeight())
        onPopupLayoutChange()
    }

    private func applyPressureThreshold() {
        guard let value = Double(viewModel.pressureThresholdText) else {
            viewModel.pressureThresholdText = String(format: "%.2f", AppPreferences.pressureThreshold())
            return
        }
        AppPreferences.setPressureThreshold(CGFloat(value))
        viewModel.pressureThresholdText = String(format: "%.2f", AppPreferences.pressureThreshold())
        notifyForceClickSettingsChange()
    }

    private func applyPressureDelta() {
        guard let value = Double(viewModel.pressureDeltaText) else {
            viewModel.pressureDeltaText = String(format: "%.2f", AppPreferences.pressureDelta())
            return
        }
        AppPreferences.setPressureDelta(CGFloat(value))
        viewModel.pressureDeltaText = String(format: "%.2f", AppPreferences.pressureDelta())
        notifyForceClickSettingsChange()
    }

    private func applyBaselineWindow() {
        guard let value = Double(viewModel.baselineWindowText) else {
            viewModel.baselineWindowText = String(format: "%.0f", AppPreferences.baselineWindowMs())
            return
        }
        AppPreferences.setBaselineWindowMs(CGFloat(value))
        viewModel.baselineWindowText = String(format: "%.0f", AppPreferences.baselineWindowMs())
        notifyForceClickSettingsChange()
    }

    private func notifyForceClickSettingsChange() {
        onForceClickSettingsChange(
            Float(AppPreferences.pressureThreshold()),
            Float(AppPreferences.pressureDelta()),
            TimeInterval(AppPreferences.baselineWindowMs() / 1000)
        )
    }
}

struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var shortcut: KeyboardShortcut
    let placeholder: String
    let onShortcutChange: (KeyboardShortcut) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderField {
        let field = ShortcutRecorderField()
        field.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        field.controlSize = .small
        field.isEditable = true
        field.isSelectable = false
        field.isBordered = false
        field.focusRingType = .none
        field.placeholderString = placeholder
        field.currentShortcut = shortcut
        field.onShortcutChange = { newShortcut in
            DispatchQueue.main.async {
                shortcut = newShortcut
                onShortcutChange(newShortcut)
            }
        }
        return field
    }

    func updateNSView(_ nsView: ShortcutRecorderField, context: Context) {
        nsView.placeholderString = placeholder
        if nsView.currentShortcut != shortcut {
            nsView.currentShortcut = shortcut
        }
    }
}
