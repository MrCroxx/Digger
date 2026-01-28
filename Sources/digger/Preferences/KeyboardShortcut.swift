import AppKit
import Carbon
import Foundation

struct KeyboardShortcut: Equatable {
    static let relevantModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

    let keyCode: CGKeyCode
    let modifiers: CGEventFlags

    init(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.relevantModifiers)
    }

    func matches(event: CGEvent) -> Bool {
        let eventKeyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let eventModifiers = event.flags.intersection(Self.relevantModifiers)
        return eventKeyCode == keyCode && eventModifiers == modifiers
    }

    func displayString() -> String {
        var parts: [String] = []
        if modifiers.contains(.maskCommand) {
            parts.append("Cmd")
        }
        if modifiers.contains(.maskControl) {
            parts.append("Ctrl")
        }
        if modifiers.contains(.maskAlternate) {
            parts.append("Opt")
        }
        if modifiers.contains(.maskShift) {
            parts.append("Shift")
        }
        parts.append(keyDisplayName())
        return parts.joined(separator: "+")
    }

    static func from(keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags) -> KeyboardShortcut? {
        let filtered = modifiers.intersection([.command, .control, .option, .shift])
        guard !filtered.isEmpty else {
            return nil
        }
        return KeyboardShortcut(keyCode: keyCode, modifiers: CGEventFlags(rawValue: UInt64(filtered.rawValue)))
    }

    private func keyDisplayName() -> String {
        if let special = Self.specialKeyName(for: keyCode) {
            return special
        }
        if let keyString = Self.keyString(for: keyCode), !keyString.isEmpty {
            return keyString.uppercased()
        }
        return "Key\(keyCode)"
    }

    private static func specialKeyName(for keyCode: CGKeyCode) -> String? {
        switch keyCode {
        case CGKeyCode(kVK_Return):
            return "Return"
        case CGKeyCode(kVK_Escape):
            return "Esc"
        case CGKeyCode(kVK_Delete):
            return "Delete"
        case CGKeyCode(kVK_ForwardDelete):
            return "ForwardDelete"
        case CGKeyCode(kVK_Tab):
            return "Tab"
        case CGKeyCode(kVK_Space):
            return "Space"
        case CGKeyCode(kVK_LeftArrow):
            return "Left"
        case CGKeyCode(kVK_RightArrow):
            return "Right"
        case CGKeyCode(kVK_UpArrow):
            return "Up"
        case CGKeyCode(kVK_DownArrow):
            return "Down"
        default:
            return nil
        }
    }

    private static func keyString(for keyCode: CGKeyCode) -> String? {
        guard let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutDataPointer = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = unsafeBitCast(layoutDataPointer, to: CFData.self) as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { rawBuffer -> OSStatus in
            guard let keyboardLayout = rawBuffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return -1
            }
            return UCKeyTranslate(
                keyboardLayout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                0,
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
        }
        guard status == noErr, length > 0 else {
            return nil
        }
        return String(utf16CodeUnits: chars, count: length)
    }
}
