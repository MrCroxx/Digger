import AppKit
import SwiftUI

struct PreferencesView: View {
    private enum PreferencesTab: String, CaseIterable, Identifiable {
        case general
        case popup
        case functions
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
    let onCustomFunctionsChange: () -> Void

    @State private var selection: PreferencesTab? = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--preview"), let index = args.firstIndex(of: "--settings-tab"),
           args.indices.contains(index + 1), let tab = PreferencesTab(rawValue: args[index + 1]) {
            return tab
        }
        #endif
        return .general
    }()
    @FocusState private var focusedField: Field?
    @State private var lastFocusedField: Field?
    @State private var promptEditorTarget: PromptEditorTarget?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 26) {
                HStack(spacing: 10) {
                    BrandMark()
                    Text("Digger").font(.system(size: 27, weight: .medium, design: .serif))
                }.padding(.top, 16)
                VStack(spacing: 5) {
                    ForEach(PreferencesTab.allCases) { tab in
                        Button {
                            if let focusedField { applyField(focusedField) }
                            focusedField = nil
                            selection = tab
                        } label: {
                            HStack(spacing: 11) {
                                Image(systemName: tab.systemImage).frame(width: 18)
                                Text(tab.title)
                                Spacer()
                            }
                            .font(.system(size: 13, weight: selection == tab ? .semibold : .regular))
                            .padding(.horizontal, 12).padding(.vertical, 11)
                            .foregroundStyle(selection == tab ? DiggerTheme.accent : DiggerTheme.muted)
                            .background(selection == tab ? DiggerTheme.soft : .clear, in: RoundedRectangle(cornerRadius: 9))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                Spacer()
            }.padding(.horizontal, 18).frame(width: 206).background(DiggerTheme.sidebar)
            Rectangle().fill(DiggerTheme.line).frame(width: 1)
            detailView
        }
        .foregroundStyle(DiggerTheme.ink).tint(DiggerTheme.accent)
        .frame(minWidth: 880, minHeight: 580)
        .onSubmit { if let focusedField { applyField(focusedField) } }
        .onDisappear { if let focusedField { applyField(focusedField) } }
        .onChange(of: focusedField) { newValue in
            if let lastFocusedField, lastFocusedField != newValue {
                applyField(lastFocusedField)
            }
            lastFocusedField = newValue
        }
        .onChange(of: viewModel.streamingEnabled) { newValue in
            AppPreferences.setTranslationStreamingEnabled(newValue)
        }
        .onChange(of: viewModel.popupAutomaticSize) { newValue in
            AppPreferences.setPopupAutomaticSize(newValue)
            onPopupLayoutChange()
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
            if !isApiTestRunning { viewModel.apiTestState = .idle }
            AppPreferences.setApiKey(newValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        .onChange(of: viewModel.endpoint) { newValue in
            if !isApiTestRunning { viewModel.apiTestState = .idle }
            AppPreferences.setEndpoint(newValue)
        }
        .onChange(of: viewModel.model) { newValue in
            if !isApiTestRunning { viewModel.apiTestState = .idle }
            AppPreferences.setModel(newValue)
        }
        .onChange(of: viewModel.thinkEffort) { newValue in
            if !isApiTestRunning { viewModel.apiTestState = .idle }
            AppPreferences.setThinkEffort(newValue)
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
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            if let focusedField { applyField(focusedField) }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text((selection ?? .general).title)
                    .font(.system(size: 30, weight: .medium, design: .serif))
                    .padding(.top, 16)
                if selection == .popup { appearancePreview }
                Surface {
                    switch selection ?? .general {
                    case .general: generalPane
                    case .popup: popupPane
                    case .functions: functionsPane
                    case .api: apiPane
                    case .cache: cachePane
                    }
                }
                Label(localized("Changes are saved automatically", "更改会自动保存", "変更は自動保存されます"), systemImage: "checkmark.circle")
                    .font(.system(size: 11)).foregroundStyle(DiggerTheme.muted)
            }.padding(32).frame(maxWidth: 840, alignment: .leading).frame(maxWidth: .infinity)
        }.background(DiggerTheme.canvas)
    }

    private var appearancePreview: some View {
        Surface {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label(localized("Preview", "效果预览", "プレビュー"), systemImage: "sparkle")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(DiggerTheme.accent)
                    Spacer()
                    Text("Digger").font(.system(size: 16, design: .serif))
                }
                Text(localized("Sample text · Aa 123", "示例文字 · Aa 123", "サンプルテキスト · Aa 123"))
                    .font(.system(size: viewModel.popupFontSize)).textSelection(.enabled)
            }
        }.opacity(viewModel.popupOpacity / 100)
    }

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 20) {
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
        VStack(alignment: .leading, spacing: 20) {
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
            Toggle(localized("Automatically fit content", "自动适应内容", "内容に合わせてサイズを調整"),
                   isOn: $viewModel.popupAutomaticSize)
            Text(viewModel.popupAutomaticSize
                 ? localized("Short selections open in a compact window. Height grows up to the limit; width stays steady during generation. Resizing manually takes over for this selection.",
                             "短选区使用紧凑窗口，高度随内容增长，到上限后滚动。生成期间宽度保持稳定；手动缩放后，本次窗口以你的调整为准。",
                             "短い選択は小さなウィンドウで表示し、高さは上限まで広がります。生成中の幅は固定され、手動リサイズが優先されます。")
                 : localized("Open at the dimensions below. Longer content scrolls inside the window.",
                             "按下面的固定尺寸打开，较长内容在窗口内滚动。",
                             "以下の固定サイズで開き、長い内容はウィンドウ内でスクロールします。"))
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LabeledContent {
                TextField("", text: $viewModel.popupMaxWidthText)
                    .preferenceInputStyle()
                    .frame(width: 160)
                    .focused($focusedField, equals: .popupMaxWidth)
            } label: {
                preferenceLabel(viewModel.popupAutomaticSize
                    ? localized("Maximum width (pt)", "最大宽度（点）", "最大幅（pt）")
                    : localized("Window width (pt)", "窗口宽度（点）", "ウィンドウの幅（pt）"))
            }
            LabeledContent {
                TextField("", text: $viewModel.popupMaxHeightText)
                    .preferenceInputStyle()
                    .frame(width: 160)
                    .focused($focusedField, equals: .popupMaxHeight)
            } label: {
                preferenceLabel(viewModel.popupAutomaticSize
                    ? localized("Maximum height (pt)", "最大高度（点）", "最大の高さ（pt）")
                    : localized("Window height (pt)", "窗口高度（点）", "ウィンドウの高さ（pt）"))
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
            VStack(alignment: .leading, spacing: 20) {
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
                    Text(localized("Enabled", "启用", "有効"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 48)
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
                Group {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(viewModel.customFunctions, id: \.id) { function in
                            HStack(spacing: 12) {
                                Toggle(localized("Enable \(function.title)", "启用 \(function.title)", "\(function.title) を有効にする"),
                                       isOn: Binding(
                                        get: { viewModel.customFunctions.first(where: { $0.id == function.id })?.isEnabled ?? false },
                                        set: { enabled in
                                            guard let index = viewModel.customFunctions.firstIndex(where: { $0.id == function.id }) else { return }
                                            viewModel.customFunctions[index].isEnabled = enabled
                                        }
                                       ))
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                                    .labelsHidden()
                                    .frame(width: 48)
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
                                        .lineLimit(3)
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
                                    Image(systemName: "trash")
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
                .frame(minHeight: 80)
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

    private var apiPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            LabeledContent {
                TextField(
                    "",
                    text: $viewModel.endpoint,
                    prompt: Text(AppPreferences.defaultEndpoint)
                        .foregroundColor(.secondary)
                )
                    .preferenceInputStyle()
                    .frame(maxWidth: .infinity)
            } label: {
                preferenceLabel(localized("API endpoint", "API 地址", "API エンドポイント"))
            }
            LabeledContent {
                SecureField("", text: $viewModel.apiKey)
                    .preferenceInputStyle()
                    .frame(maxWidth: .infinity)
            } label: {
                preferenceLabel(localized("API key", "API 密钥", "API キー"))
            }
            LabeledContent {
                TextField("", text: $viewModel.model)
                    .preferenceInputStyle()
                    .frame(maxWidth: .infinity)
            } label: {
                preferenceLabel(localized("Model", "模型", "モデル"))
            }
            LabeledContent {
                Picker("", selection: $viewModel.thinkEffort) {
                    Text(UIStrings.Preferences.thinkEffortDefault).tag("")
                    ForEach(Array(Set(["none", "minimal", "low", "medium", "high", "xhigh", viewModel.thinkEffort].filter { !$0.isEmpty })).sorted(), id: \.self) { effort in
                        Text(effort).tag(effort)
                    }
                }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
            } label: {
                preferenceLabel(localized("Reasoning effort", "推理强度", "推論の強度"))
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
        VStack(alignment: .leading, spacing: 20) {
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
            return DiggerTheme.accent
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
        }
    }

    private func applyPopupTooltipDelay() {
        guard let value = Double(viewModel.popupTooltipDelayText), value.isFinite else {
            viewModel.popupTooltipDelayText = String(format: "%.0f", AppPreferences.popupTooltipDelayMs())
            return
        }
        AppPreferences.setPopupTooltipDelayMs(CGFloat(value))
        viewModel.popupTooltipDelayText = String(format: "%.0f", AppPreferences.popupTooltipDelayMs())
    }

    private func applyPopupMaxWidth() {
        guard let value = Double(viewModel.popupMaxWidthText), value.isFinite else {
            viewModel.popupMaxWidthText = String(format: "%.0f", AppPreferences.popupMaxWidth())
            return
        }
        AppPreferences.setPopupMaxWidth(CGFloat(value))
        viewModel.popupMaxWidthText = String(format: "%.0f", AppPreferences.popupMaxWidth())
        onPopupLayoutChange()
    }

    private func applyPopupMaxHeight() {
        guard let value = Double(viewModel.popupMaxHeightText), value.isFinite else {
            viewModel.popupMaxHeightText = String(format: "%.0f", AppPreferences.popupMaxHeight())
            return
        }
        AppPreferences.setPopupMaxHeight(CGFloat(value))
        viewModel.popupMaxHeightText = String(format: "%.0f", AppPreferences.popupMaxHeight())
        onPopupLayoutChange()
    }

    private func applyTranslationCacheMaxSizeGiB() {
        guard let value = Double(viewModel.translationCacheMaxSizeGiBText), value.isFinite else {
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
        guard let value = Double(viewModel.translationCacheTTLHoursText), value.isFinite else {
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
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            MultilinePromptEditor(placeholder: placeholder, text: $text)
                .frame(minHeight: 220, maxHeight: 360)
            HStack {
                Spacer()
                Button(localized("Done", "完成", "完了")) {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .background(DiggerTheme.canvas).tint(DiggerTheme.accent)
        .frame(minWidth: 640, minHeight: 380)
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
            .padding(.vertical, 9)
            .padding(.horizontal, 10)
            .background(DiggerTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(DiggerTheme.line)
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
        .frame(width: 175, alignment: .leading)
}

private func preferenceLongLabel(_ text: String) -> some View {
    Text(text)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 260, alignment: .leading)
}
