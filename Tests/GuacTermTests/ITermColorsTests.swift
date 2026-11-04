import Foundation
@testable import GuacTerm
import XCTest

/// Every theme a person brings into GuacTerm arrives as an `.itermcolors` file
/// downloaded from somewhere, and the ~890 schemes the app ships with were
/// written by this same parser, so a mistake here is visible twice over: a file
/// that will not import at all, or one that imports and then draws an invisible
/// cursor and washed-out colours.
final class ITermColorsTests: XCTestCase {
    // MARK: - Fixtures

    /// A complete scheme as a mutable dictionary, so a test can damage exactly
    /// one part of it and leave everything else valid.
    private func itermCompleteScheme() -> [String: Any] {
        var plist: [String: Any] = [:]
        for slot in 0 ..< 16 {
            // Slot N is red N*16, which is exactly representable after the
            // 0...255 conversion, so the expected hex is just the slot number.
            plist["Ansi \(slot) Color"] = ThemePlist.color(
                red: Double(slot * 16) / 255,
                green: 0,
                blue: 0
            )
        }
        plist["Background Color"] = ThemePlist.color(from: "#101010")
        plist["Foreground Color"] = ThemePlist.color(from: "#EEEEEE")
        plist["Cursor Color"] = ThemePlist.color(from: "#FFFFFF")
        return plist
    }

    private func itermParse(_ plist: [String: Any], name: String = "Test") throws -> ParsedScheme {
        try ITermColors.parse(ThemePlist.serialized(plist), name: name)
    }

    /// The exact failure a file is reported with, since that reason is shown to
    /// the user next to the file's name and decides whether they retry.
    private func itermExpect(
        _ expected: ITermColorsError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () throws -> some Any
    ) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            XCTAssertEqual(error as? ITermColorsError, expected, file: file, line: line)
        }
    }

    // MARK: - Parsing

    /// The whole point of the parser: sixteen ANSI slots in the order iTerm2
    /// wrote them, plus the three window colours. One slot off by one and every
    /// program that prints in red prints in green.
    func testParsesEveryAnsiSlotInOrderWithItsWindowColours() throws {
        let scheme = try itermParse(itermCompleteScheme(), name: "Ramp")

        XCTAssertEqual(scheme.ansi, (0 ..< 16).map { String(format: "#%02X0000", $0 * 16) })
        XCTAssertEqual(scheme.background, "#101010")
        XCTAssertEqual(scheme.foreground, "#EEEEEE")
        XCTAssertEqual(scheme.cursor, "#FFFFFF")
        XCTAssertFalse(scheme.cursorIsFallback)
        XCTAssertEqual(scheme.name, "Ramp")
    }

    /// iTerm2 stores fractions and the terminal draws bytes. Rounding half away
    /// from zero is what stops a mid-grey 0.5 from landing on 127 in the
    /// importer and 128 in the bundled catalog, which would be two slightly
    /// different themes with the same name.
    func testFractionalComponentsRoundHalfAwayFromZero() throws {
        for (value, expected) in [
            (0.5, "#800000"),
            (1.0, "#FF0000"),
            (0.0, "#000000"),
            (0.002, "#010000"),
            (0.0019, "#000000"),
        ] {
            var plist = itermCompleteScheme()
            plist["Background Color"] = ThemePlist.color(red: value, green: 0, blue: 0)

            XCTAssertEqual(try itermParse(plist).background, expected, "component \(value)")
        }
    }

    /// Schemes in the wild sometimes store 0...255 integers where iTerm2 stores
    /// 0...1 fractions. Those are clamped, not scaled: scaling would turn a
    /// mostly-white colour into almost-black and the theme would look nothing
    /// like the screenshot the user picked it from.
    func testOversizedComponentsAreClampedInsteadOfScaled() throws {
        var integers = itermCompleteScheme()
        integers["Background Color"] = ["Red Component": 128, "Green Component": 255, "Blue Component": 0]
        XCTAssertEqual(try itermParse(integers).background, "#FFFF00")

        var ones = itermCompleteScheme()
        ones["Background Color"] = ["Red Component": 1, "Green Component": 1, "Blue Component": 0]
        XCTAssertEqual(try itermParse(ones).background, "#FFFF00")
    }

    /// A plist boolean arrives as an `NSNumber` too, so `true` used to sail
    /// through the conversion as 255: a colour the file never contained, with no
    /// error to explain where the colour came from.
    func testBooleanComponentIsRefusedInsteadOfBecomingAFullByte() {
        for flag in [true, false] {
            var plist = itermCompleteScheme()
            plist["Background Color"] = [
                "Red Component": flag,
                "Green Component": 0.5,
                "Blue Component": 0.5,
            ]

            itermExpect(.malformedColor("Background Color")) { try itermParse(plist) }
        }
    }

    /// A file missing one of the sixteen slots cannot be drawn, and the reason
    /// has to say which slot so the user can tell a truncated download from a
    /// scheme that simply is not a scheme.
    func testMissingAnsiSlotIsReportedByItsKey() {
        var plist = itermCompleteScheme()
        plist.removeValue(forKey: "Ansi 5 Color")

        itermExpect(.missingKey("Ansi 5 Color")) { try itermParse(plist) }
    }

    /// Without a background there is nothing to draw the window with, so the
    /// scheme is refused rather than silently borrowing a colour from elsewhere.
    func testMissingBackgroundIsReportedByItsKey() {
        var plist = itermCompleteScheme()
        plist.removeValue(forKey: "Background Color")

        itermExpect(.missingKey("Background Color")) { try itermParse(plist) }
    }

    /// A colour dictionary missing a channel is malformed, and the message names
    /// the colour it belongs to — "Foreground Color is not a colour" — not the
    /// component key, which means nothing to anyone reading it.
    func testMissingComponentIsReportedByTheColourItBelongsTo() {
        var plist = itermCompleteScheme()
        plist["Foreground Color"] = ["Red Component": 0.5, "Green Component": 0.5]

        itermExpect(.malformedColor("Foreground Color")) { try itermParse(plist) }
    }

    /// The realistic hand-edit: someone replaces the component dictionary with
    /// the hex string they meant, which parses as a plist but not as a colour.
    func testColourThatIsNotAComponentDictionaryIsRefused() {
        var plist = itermCompleteScheme()
        plist["Background Color"] = "#101010"

        itermExpect(.malformedColor("Background Color")) { try itermParse(plist) }
    }

    /// Files in the wild really do omit the cursor colour, and refusing those was
    /// a regression: the foreground is what iTerm2 falls back to, and it is also
    /// the one choice that is always visible against the background.
    func testAbsentCursorFallsBackToTheForeground() throws {
        var plist = itermCompleteScheme()
        plist.removeValue(forKey: "Cursor Color")

        let scheme = try itermParse(plist)

        XCTAssertEqual(scheme.cursor, scheme.foreground)
        XCTAssertTrue(scheme.cursorIsFallback)
    }

    /// A cursor colour that cannot be read is treated exactly like a missing one.
    /// The rest of the scheme is fine, so it imports and the terminal draws the
    /// foreground instead of refusing the whole theme over a cosmetic detail.
    func testUnreadableCursorAlsoFallsBackToTheForeground() throws {
        let malformedCursors: [Any] = [
            ["Red Component": true, "Green Component": 0.0, "Blue Component": 0.0],
            ["Red Component": 0.0, "Blue Component": 0.0],
            "#FFFFFF",
        ]

        for malformed in malformedCursors {
            var plist = itermCompleteScheme()
            plist["Cursor Color"] = malformed

            let scheme = try itermParse(plist)

            XCTAssertEqual(scheme.cursor, scheme.foreground)
            XCTAssertTrue(scheme.cursorIsFallback)
        }
    }

    /// iTerm2 exports XML, but other tools hand out the binary form of the same
    /// plist. Both are files a user can be given, and a scheme must import the
    /// same way whichever one they downloaded.
    func testBinaryPropertyListParsesLikeTheXMLForm() throws {
        let plist = itermCompleteScheme()
        let xml = ThemePlist.serialized(plist)
        let binary = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)

        XCTAssertEqual(
            try ITermColors.parse(binary, name: "Nord"),
            try ITermColors.parse(xml, name: "Nord")
        )
    }

    // MARK: - Files that are not schemes

    /// An empty file from a failed download, bytes that are really a zip, a
    /// truncated XML header: all of them are "not a property list", which is a
    /// different problem for the user than a scheme with a missing colour.
    func testDataThatIsNotAPropertyListIsRefused() {
        let notPlist = [
            Data(),
            Data([0x00, 0x01, 0x02, 0xFF, 0x7F]),
            Data("<".utf8),
        ]

        for data in notPlist {
            itermExpect(.notAPropertyList) { try ITermColors.parse(data, name: "Broken") }
        }
    }

    /// A plist that parses but is not a dictionary of colours — an array from
    /// some other tool, or the bare string an old-style plist can hold. Both are
    /// "not an iTerm2 colour scheme", because the file was readable and the
    /// user's next move is a different one.
    func testPropertyListThatIsNotASchemeIsRefused() throws {
        let array = try PropertyListSerialization.data(
            fromPropertyList: ["Ansi 0 Color"],
            format: .xml,
            options: 0
        )

        for data in [array, Data("hello".utf8)] {
            itermExpect(.notAScheme) { try ITermColors.parse(data, name: "Broken") }
        }
    }

    /// The picker lists a scheme under the name of the file, which is how the
    /// user recognises the file they just picked. A dotted stem has to survive
    /// whole: cutting at the first dot turns "Nord.Light" into "Nord" and the
    /// picker then shows two themes with the same name.
    func testParseNamesTheSchemeAfterTheFileStem() throws {
        let directory = try TemporaryDirectory()
        let nord = try directory.writeScheme(named: "Nord")
        let nordLight = try directory.writeScheme(named: "Nord.Light")

        XCTAssertEqual(try ITermColors.parse(contentsOf: nord).name, "Nord")
        XCTAssertEqual(try ITermColors.parse(contentsOf: nordLight).name, "Nord.Light")
    }

    /// A file that vanished between the open panel and the import, or a folder
    /// dropped on the app instead of a file, is reported the same way as any
    /// unreadable file rather than crashing the import.
    func testUnreadableFileIsReportedAsNotAPropertyList() throws {
        let directory = try TemporaryDirectory()
        let missing = directory.url.appendingPathComponent("Absent.itermcolors")

        itermExpect(.notAPropertyList) { try ITermColors.parse(contentsOf: missing) }
        itermExpect(.notAPropertyList) { try ITermColors.parse(contentsOf: directory.url) }
    }

    // MARK: - Identifiers

    /// Identifiers are persisted in `UserDefaults` and shipped inside
    /// Themes.json, so an imported "Solarized Dark" and the vendored
    /// "solarized-dark" have to be spelled the same way today as they were
    /// yesterday: lowercase ASCII words, single hyphens, no edges.
    func testSlugLowercasesAndJoinsWordsWithSingleHyphens() {
        XCTAssertEqual(ITermColors.slug("Solarized Dark"), "solarized-dark")
        XCTAssertEqual(ITermColors.slug("3024 Night"), "3024-night")
        XCTAssertEqual(ITermColors.slug("Gruvbox-Dark (Hard)"), "gruvbox-dark-hard")
        XCTAssertEqual(ITermColors.slug("Dracula+"), "dracula")
        XCTAssertEqual(ITermColors.slug("  spaced  out  "), "spaced-out")
    }

    /// Accented and full-width filenames are common from non-English blog posts.
    /// Folding them keeps the identifier ASCII, so the same scheme gets the same
    /// identifier whatever keyboard produced its filename.
    func testSlugFoldsAccentsAndFullWidthCharacters() {
        XCTAssertEqual(ITermColors.slug("Ünïcode Scheme"), "unicode-scheme")
        XCTAssertEqual(ITermColors.slug("Ｔｅｓｔ Scheme"), "test-scheme")
    }

    /// A filename with no ASCII letters in it yields an empty slug, and the
    /// caller has to cope with that rather than getting half a word. This pins
    /// the rule so a future "helpful" transliteration cannot quietly change
    /// identifiers that are already saved.
    func testSlugGivesNothingWhenThereAreNoAsciiLetters() {
        XCTAssertEqual(ITermColors.slug("スキーム"), "")
        XCTAssertEqual(ITermColors.slug("日本語"), "")
        XCTAssertEqual(ITermColors.slug(""), "")
        XCTAssertEqual(ITermColors.slug("+++"), "")
    }
}
