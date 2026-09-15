import AppKit
import Carbon

/// Register only the configured hotkey. Recognition does not depend on Accessibility;
/// that permission is checked separately when reading the selection.
@MainActor
final class GlobalShortcutMonitor {
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private(set) var registeredShortcut: KeyboardShortcut?
    private var registrationError: OSStatus?
    private var recording = false
    private var observers: [NSObjectProtocol] = []
    private var mouseMonitors: [Any] = []
    private let selectionHandler: SelectionHandler
    private let shortcutProvider: () -> KeyboardShortcut
    private static let signature: OSType = 0x44494752 // DIGR

    init(selectionHandler: SelectionHandler, shortcutProvider: @escaping () -> KeyboardShortcut = AppPreferences.popupShortcut) {
        self.selectionHandler = selectionHandler
        self.shortcutProvider = shortcutProvider
    }

    var statusDescription: String {
        let shortcut = shortcutProvider().displayString()
        if recording { return localized("Recording shortcut…", "正在录制快捷键…", "ショートカットを記録中…") }
        if let registrationError {
            return shortcut + " · " + localized("Registration failed", "注册失败", "登録失敗") + " (\(registrationError))"
        }
        guard hotKey != nil else { return shortcut + " · " + localized("Not registered", "未注册", "未登録") }
        return shortcut + " · " + (PermissionChecker.needsAttention()
            ? localized("Accessibility needed", "需要辅助功能权限", "アクセシビリティ権限が必要")
            : localized("Ready", "已就绪", "準備完了"))
    }

    @discardableResult
    func start() -> Bool {
        if eventHandler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetEventDispatcherTarget(), { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                               EventParamType(typeEventHotKeyID), nil,
                                               MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard result == noErr, id.signature == 0x44494752, id.id == 1 else { return OSStatus(eventNotHandledErr) }
                MainActor.assumeIsolated {
                    Unmanaged<GlobalShortcutMonitor>.fromOpaque(context).takeUnretainedValue().trigger()
                }
                return noErr
            }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
            guard status == noErr else {
                registrationError = status
                print("[Digger] Hotkey handler failed: \(status)")
                return false
            }
            observeChanges()
            observeOutsideClicks()
        }
        return registerShortcut()
    }

    private func registerShortcut() -> Bool {
        guard !recording else { return false }
        let shortcut = shortcutProvider()
        if hotKey != nil, registeredShortcut == shortcut { return true }
        unregisterShortcut()
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers,
                                         EventHotKeyID(signature: Self.signature, id: 1),
                                         GetEventDispatcherTarget(), UInt32(kEventHotKeyExclusive), &hotKey)
        registrationError = status == noErr ? nil : status
        guard status == noErr else {
            print("[Digger] Cannot register \(shortcut.displayString()): \(status). Check for another running Digger or a shortcut conflict.")
            selectionPopup.showNotice(title: localized("Shortcut unavailable", "快捷键不可用", "ショートカットが使用できません"),
                                      message: localized("Quit other Digger instances or choose another shortcut in Settings.", "请退出其他 Digger 进程，或在设置中更换快捷键。", "他の Digger を終了するか、設定で別のショートカットを選んでください。"))
            return false
        }
        registeredShortcut = shortcut
        print("[Digger] Shortcut registered: \(shortcut.displayString()). Accessibility: \(PermissionChecker.needsAttention() ? "missing" : "granted").")
        return true
    }

    private func trigger() {
        guard !recording else { return }
        // Keep native editing shortcuts intact in our own settings and prompt editors.
        print("[Digger] Shortcut received.")
        guard !(NSApp.isActive && NSApp.keyWindow != nil) else {
            print("[Digger] Shortcut ignored while a Digger window is focused.")
            return
        }
        guard !PermissionChecker.needsAttention() else {
            print("[Digger] Selection blocked: Accessibility permission is missing for this running build.")
            selectionPopup.showNotice(title: UIStrings.Welcome.accessibilityTitle,
                                      message: localized("Allow this running Digger build in System Settings → Privacy & Security → Accessibility, then select text in another app and try again. A rebuilt debug executable may need to be added again.", "请在系统设置 → 隐私与安全性 → 辅助功能中授权当前运行的 Digger，再回到其他应用选中文字重试。重新编译后的 Debug 程序可能需要重新添加。", "システム設定 → プライバシーとセキュリティ → アクセシビリティで現在の Digger を許可し、他のアプリでテキストを選択して再試行してください。"),
                                      needsAccessibility: true)
            return
        }
        let handler = selectionHandler
        Task.detached { await handler.handleShortcut() }
    }

    private func unregisterShortcut() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        registeredShortcut = nil
    }

    private func observeChanges() {
        for name in [KeyboardShortcut.didChange, KeyboardShortcut.recordingBegan, KeyboardShortcut.recordingEnded] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let changedName = note.name
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if changedName == KeyboardShortcut.recordingBegan {
                        self.recording = true
                        self.unregisterShortcut()
                    } else if changedName == KeyboardShortcut.recordingEnded {
                        self.recording = false
                        _ = self.registerShortcut()
                    } else if !self.recording { _ = self.registerShortcut() }
                }
            })
        }
    }

    private func observeOutsideClicks() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { _ in
            Task { @MainActor in selectionPopup.dismissIfClickOutside(NSEvent.mouseLocation) }
        }) { mouseMonitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            MainActor.assumeIsolated { selectionPopup.dismissIfClickOutside(NSEvent.mouseLocation) }
            return event
        }) { mouseMonitors.append(monitor) }
    }

    func stop() {
        unregisterShortcut()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors.removeAll()
    }
}
