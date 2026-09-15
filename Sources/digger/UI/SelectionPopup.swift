import AppKit
import SwiftUI

@MainActor let selectionPopup = SelectionPopup()

/// AppKit owns placement/focus; SwiftUI owns content. Streaming never resizes the window.
@MainActor
final class SelectionPopup {
    let model = ResultModel()
    private var panel: ResultPanel?
    var onOpenPreferences: (() -> Void)?
    var onRetry: ((String, CGPoint) -> Void)?
    var onStop: (() -> Void)?
    private var copyTask: Task<Void, Never>?

    func showLoading(original: String, near location: CGPoint, requestID: UUID, functions: [PopupFunction]) {
        model.begin(original: original, requestID: requestID, functions: functions)
        let window = ensurePanel()
        if !window.isVisible {
            let screen = NSScreen.screens.first { $0.frame.contains(location) } ?? NSScreen.main
            let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
            let size = CGSize(width: min(max(AppPreferences.popupMaxWidth(), 360), visible.width),
                              height: min(max(AppPreferences.popupMaxHeight(), 280), visible.height))
            window.setFrame(Self.frame(size: size, near: location, visibleFrame: visible), display: true)
        }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(window.contentView)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showNotice(title: String, message: String, needsAccessibility: Bool = false) {
        stop()
        showLoading(original: "", near: NSEvent.mouseLocation, requestID: UUID(), functions: [])
        model.notice = ResultModel.Notice(title: title, message: message, needsAccessibility: needsAccessibility)
    }

    func updateResult(_ text: String, for requestID: UUID, functionID: UUID, near: CGPoint,
                      isFinal: Bool, isCacheHit: Bool, isError: Bool = false) {
        model.update(text, requestID: requestID, functionID: functionID,
                     phase: isError ? .failed : (isFinal ? .complete : .streaming), cached: isCacheHit)
    }

    func markStreamingStarted(for requestID: UUID, functionID: UUID, near: CGPoint) {
        model.update("", requestID: requestID, functionID: functionID, phase: .streaming)
    }
    func applyPopupTextSize(_ size: CGFloat) { model.fontSize = size }
    func applyPopupOpacity(_ opacity: CGFloat) { model.opacity = opacity }
    func applyStrings() { model.language = AppPreferences.language() }
    func refreshLayout() {
        guard let panel, panel.isVisible else { return }
        let visible = panel.screen?.visibleFrame ?? panel.frame
        let size = CGSize(width: min(max(AppPreferences.popupMaxWidth(), 360), visible.width),
                          height: min(max(AppPreferences.popupMaxHeight(), 280), visible.height))
        panel.setFrame(Self.frame(size: size, near: CGPoint(x: panel.frame.minX - 14, y: panel.frame.maxY + 14),
                                  visibleFrame: visible), display: true)
    }

    static func frame(size: CGSize, near point: CGPoint, visibleFrame: CGRect) -> CGRect {
        let size = CGSize(width: min(size.width, visibleFrame.width), height: min(size.height, visibleFrame.height))
        return CGRect(x: min(max(point.x + 14, visibleFrame.minX), visibleFrame.maxX - size.width),
                      y: min(max(point.y - size.height - 14, visibleFrame.minY), visibleFrame.maxY - size.height),
                      width: size.width, height: size.height)
    }

    func dismissOnEscape() { if panel?.isVisible == true { dismiss() } }
    func dismissIfClickOutside(_ location: CGPoint) {
        guard let panel, panel.isVisible, !model.pinned, !panel.frame.contains(location) else { return }
        dismiss()
    }
    func openPreferences() {
        dismiss()
        onOpenPreferences?()
    }
    func stop() { onStop?(); model.stop() }
    func dismiss() { stop(); model.requestID = nil; panel?.orderOut(nil) }
    func retry() {
        guard let panel, !model.original.isEmpty else { return }
        onRetry?(model.original, CGPoint(x: panel.frame.minX, y: panel.frame.maxY))
    }
    func copy(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copyTask?.cancel()
        model.copied = true
        copyTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.model.copied = false
        }
    }

    private func ensurePanel() -> ResultPanel {
        if let panel { return panel }
        let window = ResultPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 620),
                                 styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Digger"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 360, height: 280)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = PopupHostingView(rootView: ResultView(model: model, controller: self))
        window.onDismiss = { [weak self] in self?.dismiss() }
        window.onCopy = { [weak self] includeOriginal in
            guard let self else { return }
            self.copy(self.model.combinedText(includeOriginal: includeOriginal))
        }
        panel = window
        return window
    }
}

private final class ResultPanel: NSPanel {
    var onDismiss: (() -> Void)?
    var onCopy: ((Bool) -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.charactersIgnoringModifiers == "c", flags == [.command, .shift] || flags == [.command, .option] {
            onCopy?(flags.contains(.option)); return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private struct ResultView: View {
    @ObservedObject var model: ResultModel
    let controller: SelectionPopup
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            separator
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let notice = model.notice {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(notice.title, systemImage: "info.circle")
                                .font(.system(size: 14, weight: .semibold))
                            Text(notice.message).font(.system(size: model.fontSize))
                                .lineSpacing(3).textSelection(.enabled)
                            if notice.needsAccessibility {
                                Button(UIStrings.Welcome.openAccessibilityButton) { SystemPreferencesLinks.openAccessibility() }
                                    .buttonStyle(.borderedProminent)
                            } else {
                                Button(UIStrings.Menu.preferences) { controller.openPreferences() }
                                    .buttonStyle(.bordered)
                            }
                        }
                    } else {
                        if !model.originalCollapsed { source }
                        if model.sections.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(localized("No prompts enabled", "尚未启用 Prompt", "有効なプロンプトがありません")).font(.headline)
                                Text(localized("Enable or add a prompt in Settings to get started.", "在设置中启用或添加 Prompt 后即可开始。", "設定でプロンプトを有効にするか追加してください。"))
                                Button(UIStrings.Menu.preferences) { controller.openPreferences() }
                            }
                        }
                        ForEach(model.sections) { section in
                            if section.id != model.sections.first?.id { separator }
                            resultSection(section)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
        }
        .background(DiggerTheme.paper.opacity(model.opacity / 100))
        .foregroundStyle(DiggerTheme.ink).tint(DiggerTheme.accent)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .ignoresSafeArea(.container, edges: .top)
    }

    private var separator: some View {
        Rectangle().fill(DiggerTheme.line).frame(height: 1).accessibilityHidden(true)
    }

    private var toolbar: some View {
        HStack(spacing: 2) {
            if model.notice == nil {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) { model.originalCollapsed.toggle() }
                    AppPreferences.setPopupOriginalCollapsed(model.originalCollapsed)
                } label: {
                    HStack(spacing: 5) {
                        Text(UIStrings.Popup.originalTitle).fixedSize()
                        Image(systemName: model.originalCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .font(.system(size: 11)).frame(height: 26).padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(model.originalCollapsed ? localized("Show source", "展开原文", "原文を表示") : localized("Hide source", "收起原文", "原文を隠す"))
                .accessibilityValue(model.originalCollapsed ? localized("Collapsed", "已折叠", "折りたたみ") : localized("Expanded", "已展开", "展開"))
                if model.originalCollapsed {
                    Text(verbatim: model.original.replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 11)).lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHidden(true)
                } else {
                    action("doc.on.doc", localized("Copy source", "复制原文", "原文をコピー")) { controller.copy(model.original) }
                    Spacer(minLength: 0)
                }
            } else {
                Text("Digger").font(.system(size: 11, weight: .medium)).padding(.leading, 4)
                Spacer(minLength: 0)
            }
            if model.notice == nil && !model.sections.isEmpty {
                if model.running {
                    action("stop.fill", localized("Stop", "停止", "停止")) { controller.stop() }
                } else {
                    action("arrow.clockwise", UIStrings.Popup.retry) { controller.retry() }
                }
                action(model.copied ? "checkmark" : "doc.on.doc", model.copied ? localized("Copied", "已复制", "コピーしました") : UIStrings.Popup.copyAll) {
                    controller.copy(model.combinedText(includeOriginal: false))
                }
                .foregroundStyle(model.copied ? DiggerTheme.accent : DiggerTheme.muted)
                .disabled(model.sections.allSatisfy { $0.text.isEmpty })
            }
            action(model.pinned ? "pin.fill" : "pin", localized("Keep open", "固定窗口", "固定")) { model.pinned.toggle() }
                .foregroundStyle(model.pinned ? DiggerTheme.accent : DiggerTheme.muted)
            action("gearshape", UIStrings.Menu.preferences) { controller.openPreferences() }
            action("xmark", localized("Close", "关闭", "閉じる")) { controller.dismiss() }
        }
        .foregroundStyle(DiggerTheme.muted)
        .padding(.horizontal, 8).padding(.vertical, 4)
    }

    private var source: some View {
        VStack(alignment: .leading, spacing: 6) {
            MarkdownContent(content: model.originalMarkdown, fontSize: model.fontSize)
            separator
        }
    }

    private func resultSection(_ section: ResultModel.Section) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    guard let index = model.sections.firstIndex(where: { $0.id == section.id }) else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) { model.sections[index].collapsed.toggle() }
                    AppPreferences.setPopupFunctionCollapsed(section.id, isCollapsed: model.sections[index].collapsed)
                } label: {
                    HStack(spacing: 5) {
                        Text(section.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Image(systemName: section.collapsed ? "chevron.right" : "chevron.down").font(.system(size: 8))
                    }
                    .frame(minHeight: 26).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Spacer(minLength: 0)
                if section.phase == .waiting || section.phase == .streaming {
                    ProgressView().controlSize(.mini)
                        .help(localized("Generating", "生成中", "生成中"))
                        .accessibilityLabel(localized("Generating", "生成中", "生成中"))
                } else if section.phase == .failed || section.phase == .stopped {
                    Text(section.phase == .failed ? localized("Failed", "失败", "失敗") : localized("Stopped", "已停止", "停止済み"))
                        .font(.system(size: 10))
                        .foregroundStyle(section.phase == .failed ? Color.red : DiggerTheme.muted)
                }
                action("doc.on.doc", UIStrings.Popup.copyResult) { controller.copy(section.text) }
                    .foregroundStyle(DiggerTheme.muted).disabled(section.text.isEmpty)
            }
            if !section.collapsed {
                if !section.text.isEmpty {
                    MarkdownContent(content: section.markdown, fontSize: model.fontSize)
                }
                if section.phase == .failed {
                    Button(UIStrings.Popup.retry) { controller.retry() }.buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
    }

    private func action(_ symbol: String, _ title: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol).font(.system(size: 11)).frame(width: 26, height: 26)
        }
        .buttonStyle(PopupButtonStyle()).help(title).accessibilityLabel(title)
    }
}

private struct PopupButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? DiggerTheme.soft : Color.clear,
                        in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.35)
    }
}
