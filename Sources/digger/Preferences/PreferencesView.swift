import AppKit
import SwiftUI

struct PreferencesView: View {
    private enum PreferencesTab: String, CaseIterable, Identifiable {
        case general
        case popup
        case functions
        case advanced
        case api
        case cache

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
            case .cache:
                return UIStrings.Preferences.tabCache
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
            case .cache:
                return "internaldrive"
            }
        }
    }

    private enum Field: Hashable {
        case popupTooltipDelay
        case popupMaxWidth
        case popupMaxHeight
        case translationCacheMaxSizeGiB
        case translationCacheTTLHours
        case pressureThreshold
        case pressureDelta
        case baselineWindow
    }

    private enum PromptEditorTarget: Identifiable, Equatable {
        case systemPrompt
        case customPrompt(UUID)

        var id: String {
            switch self {
            case .systemPrompt:
                return "system"
            case .customPrompt(let id):
                return id.uuidString
            }
        }
    }

    @ObservedObject var viewModel: PreferencesViewModel
    let onPopupFontSizeChange: (CGFloat) -> Void
    let onPopupOpacityChange: (CGFloat) -> Void
    let onPopupLayoutChange: () -> Void
    let onLanguageChange: () -> Void
    let onForceClickSettingsChange: (Float, Float, TimeInterval) -> Void
    let onCustomFunctionsChange: () -> Void

    @State private var selection: PreferencesTab? = .general
    @FocusState private var focusedField: Field?
    @State private var lastFocusedField: Field?
    @State private var promptEditorTarget: PromptEditorTarget?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(PreferencesTab.allCases, selection: $selection) { tab in
                    Label(tab.title, systemImage: tab.systemImage)
                        .tag(tab)
                }
                .listStyle(.sidebar)
                .applySidebarListBackground()
                Text(UIStrings.Preferences.description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .frame(width: 220)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            detailView
                .frame(minWidth: 560, maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 800, minHeight: 460)
        .onChange(of: focusedField) { newValue in
            if let lastFocusedField, lastFocusedField != newValue {
                applyField(lastFocusedField)
            }
            lastFocusedField = newValue
        }
        .onChange(of: viewModel.streamingEnabled) { newValue in
            AppPreferences.setTranslationStreamingEnabled(newValue)
        }
        .onChange(of: viewModel.startOnLogin) { newValue in
            AppPreferences.setStartOnLoginEnabled(newValue)
            StartOnLoginManager.apply(enabled: newValue)
            let currentValue = StartOnLoginManager.isEnabled()
            if currentValue != newValue {
                AppPreferences.setStartOnLoginEnabled(currentValue)
                viewModel.startOnLogin = currentValue
            }
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
        .onChange(of: viewModel.popupOpacity) { newValue in
            let clamped = min(max(newValue, 0), 100)
            if clamped != newValue {
                viewModel.popupOpacity = clamped
                return
            }
            AppPreferences.setPopupOpacity(CGFloat(clamped))
            onPopupOpacityChange(CGFloat(clamped))
        }
        .onChange(of: viewModel.apiKey) { newValue in
            AppPreferences.setApiKey(newValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        .onChange(of: viewModel.endpoint) { newValue in
            AppPreferences.setEndpoint(newValue)
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            promptEditorTarget = nil
        }
        .sheet(item: $promptEditorTarget) { target in
            PromptEditorSheet(
                title: promptEditorTitle(for: target),
                placeholder: promptEditorPlaceholder(for: target),
                text: promptEditorBinding(for: target)
            )
        }
    }

    private var detailView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text((selection ?? .general).title)
                .font(.system(size: 18, weight: .semibold))
            Divider()
                .padding(.vertical, 6)
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
                case .cache:
                    cachePane
                }
            }
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent {
                Picker("", selection: languageBinding) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
            } label: {
                preferenceLabel(UIStrings.Preferences.languageLabel)
            }
            Toggle(isOn: $viewModel.streamingEnabled) {
                preferenceLabel(UIStrings.Preferences.streamingLabel)
            }
            Toggle(isOn: $viewModel.startOnLogin) {
                preferenceLabel(UIStrings.Preferences.startOnLoginLabel)
            }
        }
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { viewModel.language },
            set: { newValue in
                guard viewModel.language != newValue else {
                    return
                }
                AppPreferences.setLanguage(newValue)
                viewModel.language = newValue
                onLanguageChange()
            }
        )
    }

    private var popupPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent {
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
            } label: {
                preferenceLabel(UIStrings.Preferences.popupFontSizeLabel)
            }
            LabeledContent {
                HStack(spacing: 12) {
                    Slider(
                        value: $viewModel.popupOpacity,
                        in: 0...100,
                        step: 1
                    )
                    Text(viewModel.popupOpacity / 100, format: .percent.precision(.fractionLength(0)))
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .trailing)
                }
            } label: {
                preferenceLabel(UIStrings.Preferences.popupOpacityLabel)
            }
            LabeledContent {
                TextField("", text: $viewModel.popupTooltipDelayText)
                    .preferenceInputStyle()
                    .frame(width: 160)
                    .focused($focusedField, equals: .popupTooltipDelay)
            } label: {
                preferenceLabel(UIStrings.Preferences.popupTooltipDelayLabel)
            }
            LabeledContent {
                ShortcutRecorderView(
                    shortcut: $viewModel.popupShortcut,
                    placeholder: UIStrings.Preferences.popupShortcutPlaceholder
                ) { newShortcut in
                    AppPreferences.setPopupShortcut(newShortcut)
                }
                .preferenceInputStyle()
                .frame(width: 180)
            } label: {
                preferenceLabel(UIStrings.Preferences.popupShortcutLabel)
            }
            LabeledContent {
                TextField("", text: $viewModel.popupMaxWidthText)
                    .preferenceInputStyle()
                    .frame(width: 160)
                    .focused($focusedField, equals: .popupMaxWidth)
            } label: {
                preferenceLabel("POPUP_MAX_WIDTH")
            }
            LabeledContent {
                TextField("", text: $viewModel.popupMaxHeightText)
                    .preferenceInputStyle()
                    .frame(width: 160)
                    .focused($focusedField, equals: .popupMaxHeight)
            } label: {
                preferenceLabel("POPUP_MAX_HEIGHT")
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
                Button {
                    openPromptEditor(.systemPrompt)
                } label: {
                    Text(previewTextOrPlaceholder(for: viewModel.systemPrompt, placeholder: UIStrings.Preferences.systemPromptPlaceholder))
                        .foregroundStyle(viewModel.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .buttonStyle(.plain)
                .preferenceInputContainerStyle()
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(UIStrings.Preferences.customFunctionsTitle)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button {
                        addFunction()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .frame(width: 24)
                    .accessibilityLabel(UIStrings.Preferences.addFunction)
                }
                Text(UIStrings.Preferences.customFunctionsDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Text(UIStrings.Preferences.functionTitleLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 160, alignment: .leading)
                    Text(UIStrings.Preferences.functionPromptLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Color.clear
                        .frame(width: 24, height: 1)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.customFunctions, id: \.id) { function in
                            HStack(spacing: 12) {
                                TextField(
                                    UIStrings.Preferences.functionTitlePlaceholder,
                                    text: binding(for: function.id, keyPath: \.title)
                                )
                                .preferenceInputStyle()
                                .frame(width: 160)

                                Button {
                                    openPromptEditor(.customPrompt(function.id))
                                } label: {
                                    Text(previewTextOrPlaceholder(for: function.prompt, placeholder: UIStrings.Preferences.functionPromptPlaceholder))
                                        .foregroundStyle(function.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .primary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .buttonStyle(.plain)
                                .preferenceInputContainerStyle()

                                Button {
                                    removeFunction(function.id)
                                } label: {
                                    Image(systemName: "minus")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .frame(width: 24)
                                .accessibilityLabel(UIStrings.Preferences.removeFunction)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 180)
                HStack {
                    Button(UIStrings.Preferences.restorePromptsLabel) {
                        restorePrompts()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Spacer()
                }
            }
        }
    }

    private var advancedPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent {
                TextField("", text: $viewModel.pressureThresholdText)
                    .preferenceInputStyle()
                    .frame(width: 160)
                    .focused($focusedField, equals: .pressureThreshold)
            } label: {
                preferenceLongLabel("FORCE_CLICK_PRESSURE_THRESHOLD")
            }
            LabeledContent {
                TextField("", text: $viewModel.pressureDeltaText)
                    .preferenceInputStyle()
                    .frame(width: 160)
                    .focused($focusedField, equals: .pressureDelta)
            } label: {
                preferenceLongLabel("FORCE_CLICK_PRESSURE_DELTA")
            }
            LabeledContent {
                TextField("", text: $viewModel.baselineWindowText)
                    .preferenceInputStyle()
                    .frame(width: 160)
                    .focused($focusedField, equals: .baselineWindow)
            } label: {
                preferenceLongLabel("FORCE_CLICK_BASELINE_WINDOW_MS")
            }
        }
    }

    private var apiPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent {
                TextField(
                    "",
                    text: $viewModel.endpoint,
                    prompt: Text(AppPreferences.defaultEndpoint)
                        .foregroundColor(.secondary)
                )
                    .preferenceInputStyle()
                    .frame(width: 260)
            } label: {
                preferenceLabel("OPENAI_ENDPOINT")
            }
            LabeledContent {
                SecureField("", text: $viewModel.apiKey)
                    .preferenceInputStyle()
                    .frame(width: 260)
            } label: {
                preferenceLabel("OPENAI_API_KEY")
            }
            LabeledContent {
                TextField("", text: $viewModel.model)
                    .preferenceInputStyle()
                    .frame(width: 260)
            } label: {
                preferenceLabel("OPENAI_MODEL")
            }
            HStack(spacing: 12) {
                Button(UIStrings.Preferences.apiTestLabel) {
                    Task {
                        await viewModel.testAPI()
                    }
                }
                .disabled(isApiTestRunning)
                if isApiTestRunning {
                    ProgressView()
                        .controlSize(.small)
                }
                if let message = apiTestMessage {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(apiTestMessageColor)
                        .lineLimit(2)
                }
            }
        }
    }

    private var cachePane: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent {
                TextField("", text: $viewModel.translationCacheMaxSizeGiBText)
                    .preferenceInputStyle()
                    .frame(width: 160)
                    .focused($focusedField, equals: .translationCacheMaxSizeGiB)
            } label: {
                preferenceLabel(UIStrings.Preferences.cacheMaxSizeLabel)
            }
            LabeledContent {
                TextField("", text: $viewModel.translationCacheTTLHoursText)
                    .preferenceInputStyle()
                    .frame(width: 160)
                    .focused($focusedField, equals: .translationCacheTTLHours)
            } label: {
                preferenceLabel(UIStrings.Preferences.cacheTTLHoursLabel)
            }
            HStack {
                Button(UIStrings.Preferences.openCacheDirectoryButton) {
                    openCacheDirectoryInFinder()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Spacer()
            }
        }
    }

    private var isApiTestRunning: Bool {
        if case .testing = viewModel.apiTestState {
            return true
        }
        return false
    }

    private var apiTestMessage: String? {
        switch viewModel.apiTestState {
        case .idle:
            return nil
        case .testing:
            return UIStrings.Preferences.apiTestInProgress
        case .success(let message), .failure(let message):
            return message
        }
    }

    private var apiTestMessageColor: Color {
        switch viewModel.apiTestState {
        case .success:
            return .green
        case .failure:
            return .red
        case .testing, .idle:
            return .secondary
        }
    }

    private func addFunction() {
        let newFunction = CustomFunction(title: UIStrings.Preferences.functionDefaultTitle, prompt: "")
        viewModel.customFunctions.append(newFunction)
        viewModel.selectedFunctionID = newFunction.id
    }

    private func restorePrompts() {
        viewModel.customFunctions = AppPreferences.defaultCustomFunctions
        viewModel.selectedFunctionID = viewModel.customFunctions.first?.id
        promptEditorTarget = nil
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
        if promptEditorTarget == .customPrompt(id) {
            promptEditorTarget = nil
        }
    }

    private func binding(for id: UUID, keyPath: WritableKeyPath<CustomFunction, String>) -> Binding<String> {
        Binding(
            get: {
                viewModel.customFunctions.first(where: { $0.id == id })?[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                guard let index = viewModel.customFunctions.firstIndex(where: { $0.id == id }) else {
                    return
                }
                viewModel.customFunctions[index][keyPath: keyPath] = newValue
            }
        )
    }

    private func applyField(_ field: Field) {
        switch field {
        case .popupTooltipDelay:
            applyPopupTooltipDelay()
        case .popupMaxWidth:
            applyPopupMaxWidth()
        case .popupMaxHeight:
            applyPopupMaxHeight()
        case .translationCacheMaxSizeGiB:
            applyTranslationCacheMaxSizeGiB()
        case .translationCacheTTLHours:
            applyTranslationCacheTTLHours()
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

    private func applyTranslationCacheMaxSizeGiB() {
        guard let value = Double(viewModel.translationCacheMaxSizeGiBText) else {
            viewModel.translationCacheMaxSizeGiBText = String(format: "%.2f", AppPreferences.translationCacheMaxSizeGiB())
            return
        }
        AppPreferences.setTranslationCacheMaxSizeGiB(value)
        viewModel.translationCacheMaxSizeGiBText = String(format: "%.2f", AppPreferences.translationCacheMaxSizeGiB())
        Task {
            await TranslationDiskCache.shared.pruneIfNeeded()
        }
    }

    private func applyTranslationCacheTTLHours() {
        guard let value = Double(viewModel.translationCacheTTLHoursText) else {
            viewModel.translationCacheTTLHoursText = String(format: "%.2f", AppPreferences.translationCacheTTLHours())
            return
        }
        AppPreferences.setTranslationCacheTTLHours(value)
        viewModel.translationCacheTTLHoursText = String(format: "%.2f", AppPreferences.translationCacheTTLHours())
        Task {
            await TranslationDiskCache.shared.pruneIfNeeded()
        }
    }

    private func openCacheDirectoryInFinder() {
        Task {
            let directoryURL = await TranslationDiskCache.shared.cacheDirectoryLocation()
            _ = await MainActor.run {
                NSWorkspace.shared.open(directoryURL)
            }
        }
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

    private func openPromptEditor(_ target: PromptEditorTarget) {
        promptEditorTarget = target
    }

    private func previewTextOrPlaceholder(for text: String, placeholder: String) -> String {
        let preview = promptPreviewText(text)
        return preview.isEmpty ? placeholder : preview
    }

    private func promptPreviewText(_ prompt: String) -> String {
        for line in prompt.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }

    private func promptEditorTitle(for target: PromptEditorTarget) -> String {
        switch target {
        case .systemPrompt:
            return UIStrings.Preferences.systemPromptTitle
        case .customPrompt(let id):
            let title = viewModel.customFunctions.first(where: { $0.id == id })?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if title.isEmpty {
                return UIStrings.Preferences.functionDefaultTitle
            }
            return title
        }
    }

    private func promptEditorPlaceholder(for target: PromptEditorTarget) -> String {
        switch target {
        case .systemPrompt:
            return UIStrings.Preferences.systemPromptPlaceholder
        case .customPrompt:
            return UIStrings.Preferences.functionPromptPlaceholder
        }
    }

    private func promptEditorBinding(for target: PromptEditorTarget) -> Binding<String> {
        switch target {
        case .systemPrompt:
            return $viewModel.systemPrompt
        case .customPrompt(let id):
            return binding(for: id, keyPath: \.prompt)
        }
    }
}

private struct MultilinePromptEditor: View {
    let placeholder: String
    @Binding var text: String
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 5)
                    .padding(.top, 2)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(.system(size: 13))
                .focused($isEditorFocused)
                .scrollContentBackgroundIfAvailable()
        }
        .preferenceInputContainerStyle()
        .onAppear {
            DispatchQueue.main.async {
                isEditorFocused = true
            }
        }
        .onTapGesture {
            isEditorFocused = true
        }
    }
}

private struct PromptEditorSheet: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            MultilinePromptEditor(placeholder: placeholder, text: $text)
                .frame(minHeight: 220, maxHeight: 360)
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 560)
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

private extension View {
    func preferenceInputStyle() -> some View {
        self
            .textFieldStyle(.plain)
            .preferenceInputContainerStyle()
    }

    func preferenceInputContainerStyle() -> some View {
        self
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor))
            )
    }

    @ViewBuilder
    func scrollContentBackgroundIfAvailable() -> some View {
        if #available(macOS 13.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }

    @ViewBuilder
    func applySidebarListBackground() -> some View {
        if #available(macOS 13.0, *) {
            self
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .windowBackgroundColor))
        } else {
            self
                .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

private func preferenceLabel(_ text: String) -> some View {
    Text(text)
        .lineLimit(1)
        .frame(width: 220, alignment: .leading)
}

private func preferenceLongLabel(_ text: String) -> some View {
    Text(text)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 260, alignment: .leading)
}
