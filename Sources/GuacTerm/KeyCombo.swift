import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut, stored in the form Carbon wants for
/// `RegisterEventHotKey`, which is the only registration API on macOS that
/// works without asking the user for Accessibility or Input Monitoring access.
struct KeyCombo: Hashable, Codable, Sendable {
    /// Virtual key code, as in `kVK_ANSI_T`.
    var keyCode: UInt16

    /// Carbon modifier mask (`cmdKey`, `shiftKey`, `optionKey`, `controlKey`).
    var carbonModifiers: UInt32

    /// The only modifiers a global hotkey can meaningfully use.
    static let relevantModifiers: UInt32 =
        .init(cmdKey | shiftKey | optionKey | controlKey)

    init(keyCode: UInt16, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers & Self.relevantModifiers
    }

    /// ⌥⌘T — one hand, close to where a terminal would live, and free on a
    /// stock macOS install.
    static let `default` = KeyCombo(
        keyCode: UInt16(kVK_ANSI_T),
        carbonModifiers: UInt32(cmdKey | optionKey)
    )

    var hasModifier: Bool {
        carbonModifiers != 0
    }

    var usesCommand: Bool {
        carbonModifiers & UInt32(cmdKey) != 0
    }

    var usesControl: Bool {
        carbonModifiers & UInt32(controlKey) != 0
    }

    var usesOption: Bool {
        carbonModifiers & UInt32(optionKey) != 0
    }

    var usesShift: Bool {
        carbonModifiers & UInt32(shiftKey) != 0
    }

    /// Modifier symbols in the order macOS prints them: ⌃⌥⇧⌘
    var modifierSymbols: String {
        var symbols = ""
        if usesControl {
            symbols += "⌃"
        }
        if usesOption {
            symbols += "⌥"
        }
        if usesShift {
            symbols += "⇧"
        }
        if usesCommand {
            symbols += "⌘"
        }
        return symbols
    }

    var keySymbol: String {
        KeyName.displayName(for: keyCode)
    }

    var displayString: String {
        modifierSymbols + keySymbol
    }

    static func from(event: NSEvent) -> KeyCombo {
        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }
        if event.modifierFlags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }
        if event.modifierFlags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if event.modifierFlags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        return KeyCombo(keyCode: event.keyCode, carbonModifiers: modifiers)
    }

    // MARK: - Codable

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        keyCode = try UInt16(container.decode(UInt32.self))
        carbonModifiers = try container.decode(UInt32.self) & Self.relevantModifiers
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(UInt32(keyCode))
        try container.encode(carbonModifiers)
    }
}

/// Turns virtual key codes into something a person can read.
enum KeyName {
    private static let specialKeys: [UInt16: String] = {
        var map: [UInt16: String] = [
            UInt16(kVK_Space): "Space",
            UInt16(kVK_Return): "↩",
            UInt16(kVK_ANSI_KeypadEnter): "⌤",
            UInt16(kVK_Tab): "⇥",
            UInt16(kVK_Delete): "⌫",
            UInt16(kVK_ForwardDelete): "⌦",
            UInt16(kVK_Escape): "⎋",
            UInt16(kVK_Help): "?⃝",
            UInt16(kVK_Home): "↖",
            UInt16(kVK_End): "↘",
            UInt16(kVK_PageUp): "⇞",
            UInt16(kVK_PageDown): "⇟",
            UInt16(kVK_LeftArrow): "←",
            UInt16(kVK_RightArrow): "→",
            UInt16(kVK_UpArrow): "↑",
            UInt16(kVK_DownArrow): "↓",
            UInt16(kVK_ANSI_KeypadClear): "⌧",
            UInt16(kVK_ISO_Section): "§",
        ]

        let functionKeys: [(UInt16, Int)] = [
            (UInt16(kVK_F1), 1), (UInt16(kVK_F2), 2), (UInt16(kVK_F3), 3),
            (UInt16(kVK_F4), 4), (UInt16(kVK_F5), 5), (UInt16(kVK_F6), 6),
            (UInt16(kVK_F7), 7), (UInt16(kVK_F8), 8), (UInt16(kVK_F9), 9),
            (UInt16(kVK_F10), 10), (UInt16(kVK_F11), 11), (UInt16(kVK_F12), 12),
            (UInt16(kVK_F13), 13), (UInt16(kVK_F14), 14), (UInt16(kVK_F15), 15),
            (UInt16(kVK_F16), 16), (UInt16(kVK_F17), 17), (UInt16(kVK_F18), 18),
            (UInt16(kVK_F19), 19), (UInt16(kVK_F20), 20),
        ]

        return map
    }()

    static let functionKeyCodes: Set<UInt16> = {
        let codes: [Int] = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8,
            kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15,
            kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
        ]
        return Set(codes.map(UInt16.init))
    }()

    static func displayName(for keyCode: UInt16) -> String {
        if let special = specialKeys[keyCode] {
            return special
        }
        if let layout = layoutCharacter(for: keyCode) {
            return layout
        }
        return "Key \(keyCode)"
    }

    /// Asks the current keyboard layout what a bare key code produces, so
    /// users on AZERTY or Dvorak see the key they actually pressed.
    private static func layoutCharacter(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawLayout = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let layoutData = Unmanaged<CFData>.fromOpaque(rawLayout).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { buffer -> String? in
            guard let base = buffer.baseAddress else { return nil }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)

            var deadKeyState: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 8)
            let status = UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
            guard status == noErr, length > 0 else { return nil }
            let string = String(utf16CodeUnits: characters, count: length)
            guard !string.isEmpty else { return nil }
            return string.uppercased()
        }
    }
}
