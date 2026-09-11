import AppKit
import Carbon

public struct Shortcut: Codable, Equatable {
    public let keyCode: UInt32
    public let modifiers: UInt32
    private static let supportedModifiers = UInt32(controlKey | optionKey | shiftKey | cmdKey)

    public static let `default` = Shortcut(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(controlKey | optionKey | cmdKey))

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers & Self.supportedModifiers
    }

    public init(event: NSEvent) {
        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
        if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
        if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    public var isValid: Bool {
        modifiers & UInt32(controlKey | cmdKey) != 0 && modifiers & ~Self.supportedModifiers == 0 && keyDetails != nil
    }

    public var displayText: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + (keyDetails?.label ?? "?")
    }

    public var keyEquivalent: String { keyDetails?.equivalent ?? "" }

    public var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    private var keyDetails: (label: String, equivalent: String)? {
        if let character = Self.printableKeys[Int(keyCode)] { return (character.uppercased(), character) }
        if let number = Self.functionKeys[Int(keyCode)] {
            return ("F\(number)", String(UnicodeScalar(0xF704 + number - 1)!))
        }
        switch Int(keyCode) {
        case kVK_Space: return ("Space", " ")
        case kVK_Return: return ("↩", "\r")
        case kVK_Tab: return ("⇥", "\t")
        case kVK_Delete: return ("⌫", "\u{8}")
        case kVK_ForwardDelete: return ("⌦", "\u{F728}")
        case kVK_LeftArrow: return ("←", "\u{F702}")
        case kVK_RightArrow: return ("→", "\u{F703}")
        case kVK_UpArrow: return ("↑", "\u{F700}")
        case kVK_DownArrow: return ("↓", "\u{F701}")
        case kVK_Home: return ("↖", "\u{F729}")
        case kVK_End: return ("↘", "\u{F72B}")
        case kVK_PageUp: return ("⇞", "\u{F72C}")
        case kVK_PageDown: return ("⇟", "\u{F72D}")
        default: return nil
        }
    }

    private static let printableKeys: [Int: String] = [
        kVK_ANSI_A: "a", kVK_ANSI_B: "b", kVK_ANSI_C: "c", kVK_ANSI_D: "d", kVK_ANSI_E: "e", kVK_ANSI_F: "f",
        kVK_ANSI_G: "g", kVK_ANSI_H: "h", kVK_ANSI_I: "i", kVK_ANSI_J: "j", kVK_ANSI_K: "k", kVK_ANSI_L: "l",
        kVK_ANSI_M: "m", kVK_ANSI_N: "n", kVK_ANSI_O: "o", kVK_ANSI_P: "p", kVK_ANSI_Q: "q", kVK_ANSI_R: "r",
        kVK_ANSI_S: "s", kVK_ANSI_T: "t", kVK_ANSI_U: "u", kVK_ANSI_V: "v", kVK_ANSI_W: "w", kVK_ANSI_X: "x",
        kVK_ANSI_Y: "y", kVK_ANSI_Z: "z", kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",",
        kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/", kVK_ANSI_Grave: "`"
    ]

    private static let functionKeys: [Int: Int] = [
        kVK_F1: 1, kVK_F2: 2, kVK_F3: 3, kVK_F4: 4, kVK_F5: 5, kVK_F6: 6, kVK_F7: 7, kVK_F8: 8,
        kVK_F9: 9, kVK_F10: 10, kVK_F11: 11, kVK_F12: 12, kVK_F13: 13, kVK_F14: 14, kVK_F15: 15,
        kVK_F16: 16, kVK_F17: 17, kVK_F18: 18, kVK_F19: 19, kVK_F20: 20
    ]
}

public enum ShortcutChangeError: Error, Equatable {
    case invalidShortcut
    case registrationFailed(OSStatus)

    public func message(in language: AppLanguage) -> String {
        switch self {
        case .invalidShortcut:
            return language.text("请至少按住 Command（⌘）或 Control（⌃），再按一个普通键。Esc 取消。", "Hold Command (⌘) or Control (⌃) with another key. Esc cancels.")
        case .registrationFailed(let status):
            return language.text("快捷键无法注册，可能已被占用（错误码 \(status)）。原快捷键保持不变。", "Could not register this shortcut; it may be in use (error \(status)). Your previous shortcut is unchanged.")
        }
    }
}
