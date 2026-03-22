import AppKit
import Carbon
import Foundation

enum HotkeyModifiers {
    static let defaultCarbonFlags: UInt = UInt(cmdKey | shiftKey)

    static func carbonFlags(from modifiers: NSEvent.ModifierFlags) -> UInt {
        var flags: UInt = 0
        if modifiers.contains(.command) { flags |= UInt(cmdKey) }
        if modifiers.contains(.option) { flags |= UInt(optionKey) }
        if modifiers.contains(.control) { flags |= UInt(controlKey) }
        if modifiers.contains(.shift) { flags |= UInt(shiftKey) }
        return flags
    }

    static func displayName(for modifiers: NSEvent.ModifierFlags) -> String {
        var names: [String] = []
        if modifiers.contains(.command) { names.append("⌘") }
        if modifiers.contains(.option) { names.append("⌥") }
        if modifiers.contains(.control) { names.append("⌃") }
        if modifiers.contains(.shift) { names.append("⇧") }
        return names.joined()
    }

    static func displayKey(for keyCode: UInt16) -> String {
        if let key = keyName(for: keyCode) {
            return key.uppercased()
        }
        return String(keyCode)
    }

    private static func keyName(for keyCode: UInt16) -> String? {
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        guard let rawLayoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = unsafeBitCast(rawLayoutData, to: CFData.self)
        let layoutPtr = CFDataGetBytePtr(layoutData)
        let keyboardLayout = unsafeBitCast(layoutPtr, to: UnsafePointer<UCKeyboardLayout>.self)
        var deadKeyState: UInt32 = 0
        var unicodeScalar = [UniChar](repeating: 0, count: 4)
        var length = 0
        let modifierKeyState: UInt32 = 0
        let keyTranslateResult = UCKeyTranslate(
            keyboardLayout,
            keyCode,
            UInt16(kUCKeyActionDisplay),
            modifierKeyState,
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            unicodeScalar.count,
            &length,
            &unicodeScalar
        )
        guard keyTranslateResult == noErr else {
            return nil
        }
        return String(utf16CodeUnits: unicodeScalar, count: length)
    }
}

enum SingleKeyMapping {
    static func keyCodes(for key: SingleKey) -> Set<CGKeyCode> {
        switch key {
        case .shift: return [56, 60]
        case .control: return [59, 62]
        case .option: return [58, 61]
        case .command: return [55, 54]
        case .fn: return [63]
        }
    }

    static func modifierFlag(for key: SingleKey) -> NSEvent.ModifierFlags {
        switch key {
        case .shift:
            return .shift
        case .control:
            return .control
        case .option:
            return .option
        case .command:
            return .command
        case .fn:
            return .function
        }
    }

    static func matches(keyCode: CGKeyCode, for key: SingleKey) -> Bool {
        keyCodes(for: key).contains(keyCode)
    }
}

extension NSEvent.ModifierFlags {
    init(carbonFlags: UInt) {
        var flags: NSEvent.ModifierFlags = []
        if carbonFlags & UInt(cmdKey) != 0 { flags.insert(.command) }
        if carbonFlags & UInt(optionKey) != 0 { flags.insert(.option) }
        if carbonFlags & UInt(controlKey) != 0 { flags.insert(.control) }
        if carbonFlags & UInt(shiftKey) != 0 { flags.insert(.shift) }
        self = flags
    }
}
