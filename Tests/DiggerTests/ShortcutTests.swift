import AppKit
import Carbon
import Testing
@testable import digger

struct ShortcutTests {
    @Test func commandControlEUsesCarbonModifierBits() {
        let shortcut = KeyboardShortcut(keyCode: CGKeyCode(kVK_ANSI_E), modifiers: [.maskCommand, .maskControl])
        #expect(shortcut.carbonModifiers == UInt32(cmdKey | controlKey))
        #expect(shortcut.carbonModifiers != UInt32(shortcut.modifiers.rawValue))
    }

    @Test func recorderAndEventMatchingAgreeOnCommandControlE() throws {
        let shortcut = try #require(KeyboardShortcut.from(keyCode: CGKeyCode(kVK_ANSI_E), modifiers: [.command, .control, .capsLock]))
        let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_E), keyDown: true))
        event.flags = [.maskCommand, .maskControl, .maskAlphaShift]
        #expect(shortcut.matches(event: event))
        event.flags = [.maskCommand]
        #expect(!shortcut.matches(event: event))
        #expect(shortcut.carbonModifiers == UInt32(cmdKey | controlKey))
    }

    @Test func allSupportedModifiersMapWithoutUnrelatedFlags() {
        let shortcut = KeyboardShortcut(keyCode: 14, modifiers: [.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn])
        #expect(shortcut.carbonModifiers == UInt32(cmdKey | controlKey | optionKey | shiftKey))
    }
}

@MainActor
struct HotKeyRegistrationTests {
    @Test func editingShortcutUnregistersThenRegistersTheNewBinding() {
        _ = NSApplication.shared
        var binding = KeyboardShortcut(keyCode: CGKeyCode(kVK_F19), modifiers: [.maskCommand, .maskControl, .maskShift])
        let monitor = GlobalShortcutMonitor(selectionHandler: SelectionHandler(), shortcutProvider: { binding })
        defer { monitor.stop() }
        #expect(monitor.start())
        #expect(monitor.registeredShortcut == binding)
        NotificationCenter.default.post(name: KeyboardShortcut.recordingBegan, object: nil)
        #expect(monitor.registeredShortcut == nil)
        binding = KeyboardShortcut(keyCode: CGKeyCode(kVK_F18), modifiers: [.maskCommand, .maskControl, .maskShift])
        NotificationCenter.default.post(name: KeyboardShortcut.didChange, object: nil)
        #expect(monitor.registeredShortcut == nil)
        NotificationCenter.default.post(name: KeyboardShortcut.recordingEnded, object: nil)
        #expect(monitor.registeredShortcut == binding)
        #expect(monitor.start()) // Already registered is idempotent.
        monitor.stop()
        #expect(monitor.registeredShortcut == nil)
    }
}
