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
    private var isFocused: Bool = false {
        didSet {
            updateFocusAppearance()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureFocusAppearance()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureFocusAppearance()
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        if didBecome {
            startMonitoring()
            isFocused = true
        }
        return didBecome
    }

    override func resignFirstResponder() -> Bool {
        stopMonitoring()
        isFocused = false
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateFocusAppearance()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        return handleShortcutEvent(event)
    }

    private func handleShortcutEvent(_ event: NSEvent) -> Bool {
        guard isShortcutFocused else {
            return false
        }
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

    private var isShortcutFocused: Bool {
        guard let window else {
            return false
        }
        if window.firstResponder === self {
            return true
        }
        if let editor = currentEditor(), window.firstResponder === editor {
            return true
        }
        return false
    }

    private func configureFocusAppearance() {
        wantsLayer = true
        layer?.cornerRadius = 6
        drawsBackground = true
        updateFocusAppearance()
    }

    private func updateFocusAppearance() {
        guard let layer else {
            return
        }
        let appearance = window?.effectiveAppearance ?? NSAppearance.currentDrawing()
        if isFocused {
            layer.borderWidth = 1.5
            layer.borderColor = NSColor.controlAccentColor.withAlpha(1, for: appearance)
            backgroundColor = NSColor.controlAccentColor.withDynamicAlpha(0.08)
        } else {
            layer.borderWidth = 1.0
            layer.borderColor = NSColor.separatorColor.withAlpha(1, for: appearance)
            backgroundColor = NSColor.textBackgroundColor
        }
    }
}
