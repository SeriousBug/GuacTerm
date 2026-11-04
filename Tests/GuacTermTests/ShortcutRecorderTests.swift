import AppKit
import Carbon.HIToolbox
@testable import GuacTerm
import XCTest

/// The recorder is where a user sets the one shortcut that opens the terminal,
/// so every key press in it has to end somewhere sensible: a combination with a
/// modifier becomes the hotkey, Escape and Delete back out without losing the
/// old one, and a bare letter is refused instead of stealing that key from every
/// other app. What the capsule shows afterwards is what the menu-bar tooltip
/// repeats, so it has to be readable.
@MainActor
final class ShortcutRecorderTests: XCTestCase {
    /// A recorder with nothing listening for changes.
    private func makeRecorder(combo: KeyCombo = .default) -> ShortcutRecorderView {
        let view = ShortcutRecorderView(frame: NSRect(x: 0, y: 0, width: 132, height: 26))
        view.combo = combo
        return view
    }

    /// Puts the recorder into the state a click leaves it in, and checks the
    /// click actually got there — a view that never starts recording would make
    /// every test below pass for the wrong reason.
    private func startRecording(_ view: ShortcutRecorderView) {
        XCTAssertTrue(view.becomeFirstResponder())
        XCTAssertTrue(view.isRecording)
    }

    /// Presses one key on the recorder, as AppKit would while it records.
    private func press(
        _ keyCode: Int,
        modifiers: NSEvent.ModifierFlags = [],
        characters: String = "t",
        on view: ShortcutRecorderView
    ) {
        guard let event = keyEvent(
            keyCode: UInt16(keyCode),
            modifiers: modifiers,
            characters: characters
        ) else {
            return XCTFail("no key event for key code \(keyCode)")
        }
        view.keyDown(with: event)
    }

    // MARK: - Combinations that become the hotkey

    func testACommandShortcutIsRecordedReportedAndEndsRecording() {
        let view = makeRecorder()
        var changes: [KeyCombo] = []
        view.onChange = { changes.append($0) }

        startRecording(view)
        press(kVK_ANSI_T, modifiers: [.command], characters: "t", on: view)

        // The new value has to reach the settings binding, or the capsule shows
        // one shortcut while the registered hotkey is another.
        XCTAssertEqual(view.combo, KeyCombo(keyCode: UInt16(kVK_ANSI_T), carbonModifiers: UInt32(cmdKey)))
        XCTAssertEqual(changes, [view.combo])
        XCTAssertFalse(view.isRecording)
    }

    func testTheRecordedShortcutKeepsEveryModifierThatWasHeld() {
        // All four are legal on one hotkey, and losing any of them would
        // register a shortcut that fires on the wrong keystroke — or on a
        // weaker one the user never chose.
        let view = makeRecorder()

        startRecording(view)
        press(kVK_ANSI_K, modifiers: [.command, .shift, .option, .control], characters: "k", on: view)

        XCTAssertEqual(view.combo.carbonModifiers, UInt32(cmdKey | shiftKey | optionKey | controlKey))
        XCTAssertEqual(view.combo.displayString, "⌃⌥⇧⌘" + KeyName.displayName(for: UInt16(kVK_ANSI_K)))
    }

    func testABareFunctionKeyBecomesTheHotkeyAndReadsAsItsName() {
        // Function keys are the one combination allowed without a modifier, and
        // the capsule has to say "F1" rather than printing the control character
        // the keyboard layout reports for that key code.
        let view = makeRecorder()
        var changes: [KeyCombo] = []
        view.onChange = { changes.append($0) }

        startRecording(view)
        press(kVK_F1, on: view)

        XCTAssertEqual(view.combo, KeyCombo(keyCode: UInt16(kVK_F1), carbonModifiers: 0))
        XCTAssertEqual(view.combo.displayString, "F1")
        XCTAssertEqual(changes.count, 1)
        XCTAssertFalse(view.isRecording)
    }

    // MARK: - Ways out of recording

    func testEscapeLeavesTheShortcutAlone() {
        // Escape is the way out, so it must not become the shortcut or be
        // reported to the settings row.
        let view = makeRecorder()
        var changes: [KeyCombo] = []
        view.onChange = { changes.append($0) }

        startRecording(view)
        press(kVK_Escape, modifiers: [.command], on: view)

        XCTAssertEqual(view.combo, .default)
        XCTAssertTrue(changes.isEmpty)
        XCTAssertFalse(view.isRecording)
    }

    func testDeleteLeavesTheShortcutAlone() {
        // Same back-out, on the key a person reaches for first. It beeps on
        // purpose, so the cancel is not silent and puzzling.
        let view = makeRecorder()
        var changes: [KeyCombo] = []
        view.onChange = { changes.append($0) }

        startRecording(view)
        press(kVK_Delete, modifiers: [.command], on: view)

        XCTAssertEqual(view.combo, .default)
        XCTAssertTrue(changes.isEmpty)
        XCTAssertFalse(view.isRecording)
    }

    func testForwardDeleteAlsoCancelsRecording() {
        // The full keyboard's ⌦ sits where Backspace is on a laptop, so backing
        // out must not depend on which delete key was pressed.
        let view = makeRecorder()

        startRecording(view)
        press(kVK_ForwardDelete, on: view)

        XCTAssertEqual(view.combo, .default)
        XCTAssertFalse(view.isRecording)
    }

    func testABareLetterIsRefusedAndRecordingCarriesOn() {
        // A global hotkey on a plain letter would swallow that letter in every
        // app, so the recorder stays open and waits for a real combination.
        let view = makeRecorder()
        var changes: [KeyCombo] = []
        view.onChange = { changes.append($0) }

        startRecording(view)
        press(kVK_ANSI_A, characters: "a", on: view)

        XCTAssertEqual(view.combo, .default)
        XCTAssertTrue(changes.isEmpty)
        XCTAssertTrue(view.isRecording)

        // And the combination the user settles on next still lands.
        press(kVK_ANSI_T, modifiers: [.command], characters: "t", on: view)

        XCTAssertEqual(view.combo.carbonModifiers, UInt32(cmdKey))
        XCTAssertEqual(changes.count, 1)
        XCTAssertFalse(view.isRecording)
    }

    // MARK: - Layout

    func testTheCapsuleReportsTheFixedSizeTheSettingsRowReserves() {
        // The settings row lays the capsule out at its intrinsic size, so this
        // size decides how wide a column the "Toggle Shortcut" row gets.
        let view = makeRecorder()

        XCTAssertEqual(view.intrinsicContentSize, NSSize(width: 132, height: 26))
    }
}
