import AppKit
import Carbon.HIToolbox
@testable import GuacTerm
import XCTest

/// The toggle shortcut is the only way into a drop-down terminal without the
/// Dock, so it has to come back exactly as the user picked it: the Carbon mask
/// has to keep the four modifiers a hotkey can use and nothing else, the stored
/// form has to survive a round trip through the defaults, and a stored value the
/// app cannot read must not take the launch down with it.
@MainActor
final class KeyComboTests: XCTestCase {
    /// Modifier bits outside the four a global hotkey can register — caps lock,
    /// and whatever else AppKit or a future macOS reports in the same mask.
    private static let unusableModifierBits: UInt32 = 0x0001_0000 | 0x0000_0001 | 0x0040_0000

    /// Reads a combo from the JSON spelling of its stored form, which is the
    /// same shape a defaults plist holds.
    private func combo(fromJSON json: String) throws -> KeyCombo {
        try JSONDecoder().decode(KeyCombo.self, from: Data(json.utf8))
    }

    // MARK: - Building a combo

    func testOnlyTheFourHotkeyModifiersSurviveInitialisation() {
        // Anything else in the mask would be registered with Carbon as a
        // different shortcut than the one the user was shown.
        let everything = KeyCombo(keyCode: UInt16(kVK_ANSI_T), carbonModifiers: UInt32.max)
        XCTAssertEqual(everything.carbonModifiers, KeyCombo.relevantModifiers)
        XCTAssertEqual(everything.carbonModifiers, UInt32(cmdKey | shiftKey | optionKey | controlKey))

        let garbageOnly = KeyCombo(keyCode: UInt16(kVK_ANSI_T), carbonModifiers: Self.unusableModifierBits)
        XCTAssertEqual(garbageOnly.carbonModifiers, 0)
        XCTAssertFalse(garbageOnly.hasModifier)
    }

    func testTheDefaultShortcutIsOptionCommandT() {
        let combo = KeyCombo.default

        XCTAssertEqual(combo.keyCode, UInt16(kVK_ANSI_T))
        XCTAssertEqual(combo.carbonModifiers, UInt32(cmdKey | optionKey))
        XCTAssertTrue(combo.usesCommand)
        XCTAssertTrue(combo.usesOption)
        XCTAssertFalse(combo.usesControl)
        XCTAssertFalse(combo.usesShift)
        XCTAssertEqual(combo.modifierSymbols, "⌥⌘")
    }

    func testTheDefaultShortcutIsWrittenTheWayTheMenuBarTooltipShowsIt() {
        // The letter comes from the live keyboard layout — an AZERTY or Dvorak
        // user sees the key they actually press — so only the shape of the
        // string is fixed here, not the letter.
        let combo = KeyCombo.default

        XCTAssertEqual(combo.keySymbol, KeyName.displayName(for: UInt16(kVK_ANSI_T)))
        XCTAssertEqual(combo.displayString, combo.modifierSymbols + combo.keySymbol)
        XCTAssertTrue(combo.displayString.hasPrefix("⌥⌘"))
    }

    func testAllFourModifiersPrintInTheOrderMacOSUses() {
        let combo = KeyCombo(
            keyCode: UInt16(kVK_ANSI_T),
            carbonModifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey)
        )
        XCTAssertEqual(combo.modifierSymbols, "⌃⌥⇧⌘")
    }

    func testABareKeyCarriesNoModifier() {
        // The recorder relies on this to refuse a combination that would swallow
        // ordinary typing for the whole system.
        let bare = KeyCombo(keyCode: UInt16(kVK_ANSI_T), carbonModifiers: 0)

        XCTAssertFalse(bare.hasModifier)
        XCTAssertEqual(bare.modifierSymbols, "")
        XCTAssertEqual(bare.displayString, bare.keySymbol)
    }

    // MARK: - Reading a key press

    func testCommandAndOptionInAnEventBecomeTheCarbonBits() throws {
        let event = try XCTUnwrap(keyEvent(keyCode: UInt16(kVK_ANSI_T), modifiers: [.command, .option]))
        let combo = KeyCombo.from(event: event)

        XCTAssertEqual(combo.keyCode, UInt16(kVK_ANSI_T))
        XCTAssertEqual(combo.carbonModifiers, UInt32(cmdKey | optionKey))
        XCTAssertEqual(combo, KeyCombo.default)
    }

    func testModifierFlagsCarbonCannotRegisterAreIgnored() throws {
        // Caps lock, fn and the numeric pad arrive in the same flag set as the
        // real modifiers; letting them through would make the hotkey impossible
        // to register, or register it under a mask nobody can press again.
        let event = try XCTUnwrap(keyEvent(
            keyCode: UInt16(kVK_ANSI_T),
            modifiers: [.command, .capsLock, .function, .numericPad]
        ))
        XCTAssertEqual(KeyCombo.from(event: event).carbonModifiers, UInt32(cmdKey))
    }

    func testOneEventCanCarryAllFourModifiers() throws {
        let event = try XCTUnwrap(keyEvent(
            keyCode: UInt16(kVK_ANSI_T),
            modifiers: [.command, .shift, .option, .control]
        ))
        let combo = KeyCombo.from(event: event)

        XCTAssertEqual(combo.carbonModifiers, UInt32(cmdKey | shiftKey | optionKey | controlKey))
        XCTAssertEqual(combo.displayString, "⌃⌥⇧⌘" + KeyName.displayName(for: UInt16(kVK_ANSI_T)))
    }

    // MARK: - Storage

    func testAStoredShortcutComesBackUnchanged() throws {
        let combo = KeyCombo(
            keyCode: UInt16(kVK_ANSI_R),
            carbonModifiers: UInt32(controlKey | shiftKey)
        )
        let decoded = try JSONDecoder().decode(KeyCombo.self, from: JSONEncoder().encode(combo))

        XCTAssertEqual(decoded, combo)
        XCTAssertEqual(decoded.displayString, combo.displayString)
    }

    func testTheStoredFormIsAPairOfNumbers() throws {
        // It lands in a defaults plist read by older builds too, so the layout
        // is part of what is on disk: key code first, modifier mask second.
        let pair = try JSONDecoder().decode([UInt32].self, from: JSONEncoder().encode(KeyCombo.default))

        XCTAssertEqual(pair, [UInt32(kVK_ANSI_T), UInt32(cmdKey | optionKey)])
    }

    func testDecodingDropsModifierBitsItDoesNotKnow() throws {
        let json = "[\(UInt32(kVK_ANSI_T)), \(UInt32(cmdKey) | Self.unusableModifierBits)]"
        let combo = try combo(fromJSON: json)

        XCTAssertEqual(combo.carbonModifiers, UInt32(cmdKey))
        XCTAssertEqual(combo.keySymbol, KeyName.displayName(for: UInt16(kVK_ANSI_T)))
    }

    func testDecodingRefusesAKeyCodeLargerThanSixteenBits() {
        // The regression: this used to be squeezed into a UInt16 with
        // `UInt16(...)`, which traps. It runs while the app reads its defaults
        // at launch, so one stored value above 65535 crashed GuacTerm on every
        // start — and `try?` never got the chance to fall back to the default.
        XCTAssertThrowsError(try combo(fromJSON: "[70000, \(UInt32(cmdKey | optionKey))]"))

        // The same trap, wherever in the stored pair it sits and however bad.
        XCTAssertThrowsError(try combo(fromJSON: "[65536, \(UInt32(cmdKey))]"))
        XCTAssertThrowsError(try combo(fromJSON: "[\(UInt32.max), \(UInt32(cmdKey))]"))
    }

    func testDecodingAcceptsAKeyCodeAtTheEdgeOfSixteenBits() throws {
        // The refusal above has to be about the range and nothing else, or a
        // real shortcut would stop being read.
        let combo = try combo(fromJSON: "[65535, \(UInt32(cmdKey))]")

        XCTAssertEqual(combo.keyCode, 65535)
        XCTAssertEqual(combo.carbonModifiers, UInt32(cmdKey))
    }

    func testDecodingRefusesSomethingThatIsNotJSONAtAll() {
        XCTAssertThrowsError(try combo(fromJSON: "garbage"))
    }

    func testDecodingRefusesHalfAPair() {
        // A truncated write — the app quit mid-save, say — has a key code but
        // no modifier mask, and a shortcut with no modifiers would swallow the
        // key everywhere.
        XCTAssertThrowsError(try combo(fromJSON: "[17]"))
    }

    func testDecodingRefusesTheKeyedShapeSomeoneMightHandWrite() {
        // `{"keyCode": 17, "carbonModifiers": 256}` looks reasonable in a plist
        // editor, but it is not the form the app writes.
        XCTAssertThrowsError(try combo(fromJSON: #"{"keyCode":17,"carbonModifiers":256}"#))
    }

    // MARK: - Key names

    func testSpecialKeysReadAsTheSymbolsMacOSPrints() {
        // These are what the recorder capsule and the menu-bar tooltip show; a
        // raw control character there is unreadable.
        let expected: [(Int, String)] = [
            (kVK_Space, "Space"),
            (kVK_Return, "↩"),
            (kVK_Tab, "⇥"),
            (kVK_Escape, "⎋"),
            (kVK_Delete, "⌫"),
            (kVK_ForwardDelete, "⌦"),
            (kVK_LeftArrow, "←"),
            (kVK_RightArrow, "→"),
            (kVK_UpArrow, "↑"),
            (kVK_DownArrow, "↓"),
            (kVK_PageUp, "⇞"),
            (kVK_PageDown, "⇟"),
            (kVK_Home, "↖"),
            (kVK_End, "↘"),
        ]

        for (code, symbol) in expected {
            XCTAssertEqual(
                KeyName.displayName(for: UInt16(code)),
                symbol,
                "key code \(code) should read as \(symbol)"
            )
        }
    }

    func testFunctionKeysReadAsF1ToF20() {
        // The regression: the F-key table was built and then never merged into
        // the lookup, so F1 fell through to the keyboard layout, which answers
        // with the control character it sends — "\u{10}" in the recorder.
        XCTAssertEqual(KeyName.displayName(for: UInt16(kVK_F1)), "F1")
        XCTAssertEqual(KeyName.displayName(for: UInt16(kVK_F20)), "F20")

        for code in KeyName.functionKeyCodes {
            let name = KeyName.displayName(for: code)
            XCTAssertTrue(name.hasPrefix("F"), "key code \(code) should read as an F-key, got \(name)")
            XCTAssertNil(
                name.unicodeScalars.first { CharacterSet.controlCharacters.contains($0) },
                "key code \(code) reads as a control character: \(name.debugDescription)"
            )
        }
    }

    func testTheFunctionKeyTableHasAllTwentyKeysAndAgreesWithTheirNames() {
        XCTAssertEqual(KeyName.functionKeyCodes.count, 20)

        let fromConstants: [UInt16] = [
            UInt16(kVK_F1), UInt16(kVK_F2), UInt16(kVK_F3), UInt16(kVK_F4),
            UInt16(kVK_F5), UInt16(kVK_F6), UInt16(kVK_F7), UInt16(kVK_F8),
            UInt16(kVK_F9), UInt16(kVK_F10), UInt16(kVK_F11), UInt16(kVK_F12),
            UInt16(kVK_F13), UInt16(kVK_F14), UInt16(kVK_F15), UInt16(kVK_F16),
            UInt16(kVK_F17), UInt16(kVK_F18), UInt16(kVK_F19), UInt16(kVK_F20),
        ]
        XCTAssertEqual(KeyName.functionKeyCodes, Set(fromConstants))

        for (index, code) in fromConstants.enumerated() {
            XCTAssertEqual(KeyName.displayName(for: code), "F\(index + 1)")
        }
    }

    func testAnUnknownKeyCodeStillSaysSomething() {
        // An empty capsule for a key the layout has no answer for would look
        // like the recorder had stopped working. Both codes are above the 128
        // entries a keyboard layout's key map has, so no layout can name them.
        XCTAssertEqual(KeyName.displayName(for: 0xFFFF), "Key 65535")
        XCTAssertEqual(KeyName.displayName(for: 0xFF), "Key 255")
    }
}
