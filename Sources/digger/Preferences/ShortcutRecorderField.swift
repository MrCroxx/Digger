import AppKit
import Carbon
import Foundation

final class ShortcutRecorderField: NSTextField {
    var onShortcutChange: ((KeyboardShortcut) -> Void)?
    var currentShortcut: KeyboardShortcut? {
        didSet {
            stringValue = currentShortcut?.displayString() ?? ""
        }
    }
    private var localMonitor: Any?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        if didBecome {
            startMonitoring()
        }
        return didBecome
    }

    override func resignFirstResponder() -> Bool {
        stopMonitoring()
        return super.resignFirstResponder()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if handleShortcutEvent(event) {
            return
        }
        NSSound.beep()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        return handleShortcutEvent(event)
    }

    private func handleShortcutEvent(_ event: NSEvent) -> Bool {
        if event.keyCode == CGKeyCode(kVK_Escape) {
            window?.makeFirstResponder(nil)
            return true
        }
        guard let shortcut = KeyboardShortcut.from(keyCode: CGKeyCode(event.keyCode), modifiers: event.modifierFlags) else {
            return false
        }
        currentShortcut = shortcut
        onShortcutChange?(shortcut)
        window?.makeFirstResponder(nil)
        return true
    }

    private func startMonitoring() {
        if localMonitor != nil {
            return
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, event.window == self.window else {
                return event
            }
            if self.handleShortcutEvent(event) {
                return nil
            }
            return event
        }
    }

    private func stopMonitoring() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }
}
