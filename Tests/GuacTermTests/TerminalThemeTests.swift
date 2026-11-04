@testable import GuacTerm
import SwiftTerm
import XCTest

/// A theme is three window colours and sixteen ANSI ones, and how those are
/// judged decides what the terminal looks like: too pale a comment, a cursor the
/// same colour as the text behind it, a light window with a light border. These
/// tests pin the colour maths the whole app draws with.
@MainActor
final class TerminalThemeTests: XCTestCase {
    // MARK: - Fixtures

    /// The step `ThemeLibrary` performs after parsing a file: a `ParsedScheme`
    /// becomes a theme with an identifier. Kept here so the imported side of a
    /// comparison is built exactly the way the real importer builds it.
    private func terminalTheme(from scheme: ParsedScheme, id: String = "imported-test") -> TerminalTheme {
        TerminalTheme(
            id: id,
            name: scheme.name,
            background: scheme.background,
            foreground: scheme.foreground,
            cursor: scheme.cursor,
            ansi: scheme.ansi
        )
    }

    /// A theme written out as the `.itermcolors` file it could have come from, so
    /// a bundled scheme can be pushed through the importer and back.
    private func terminalThemeSchemeFile(for theme: TerminalTheme) -> Data {
        var plist: [String: Any] = [:]
        for (slot, hex) in theme.ansi.enumerated() {
            plist["Ansi \(slot) Color"] = ThemePlist.color(from: hex)
        }
        plist["Background Color"] = ThemePlist.color(from: theme.background)
        plist["Foreground Color"] = ThemePlist.color(from: theme.foreground)
        plist["Cursor Color"] = ThemePlist.color(from: theme.cursor)
        return ThemePlist.serialized(plist)
    }

    // MARK: - Reading a colour

    /// Themes.json and hand-edited files both carry `#RRGGBB`, but a leading `#`
    /// and stray whitespace are the two things people leave off and add. Anything
    /// else — five digits, eight, a letter past F — is a colour the app cannot
    /// draw, so the picker has to reject it before it becomes black on screen.
    func testHexColourCheckAcceptsSixDigitsWithOrWithoutTheHash() {
        XCTAssertTrue(TerminalTheme.isHexColor("#102030"))
        XCTAssertTrue(TerminalTheme.isHexColor("102030"))
        XCTAssertTrue(TerminalTheme.isHexColor("  #102030  "))
        XCTAssertTrue(TerminalTheme.isHexColor("#abcdef"))

        XCTAssertFalse(TerminalTheme.isHexColor("#10203"))
        XCTAssertFalse(TerminalTheme.isHexColor("#1020304"))
        XCTAssertFalse(TerminalTheme.isHexColor("#10203040"))
        XCTAssertFalse(TerminalTheme.isHexColor("#10203G"))
        XCTAssertFalse(TerminalTheme.isHexColor(""))

        // A sign is not a hex digit, even though the integer parser that reads
        // the six characters would happily take one. Six digits plus a sign is
        // the case that used to pass here and then draw black.
        XCTAssertFalse(TerminalTheme.isHexColor("#+F0000"))
        XCTAssertFalse(TerminalTheme.isHexColor("+FF000"))
        XCTAssertFalse(TerminalTheme.isHexColor("#-0000F"))
        XCTAssertFalse(TerminalTheme.isHexColor("#"))
    }

    /// The three-digit shorthand is deliberately not a theme colour. It is
    /// accepted by `NSColor(hex:)`, so this is an asymmetry rather than an
    /// oversight: a catalog entry of `#ABC` would draw a colour the theme never
    /// spelled out, and the loader rejects it instead.
    func testHexColourCheckRejectsTheThreeDigitShorthand() {
        XCTAssertFalse(TerminalTheme.isHexColor("#ABC"))
        XCTAssertFalse(TerminalTheme.isHexColor("ABC"))

        // The other half of the asymmetry, so the difference stays on purpose.
        XCTAssertEqual(NSColor(hex: "#ABC").hexString, "#AABBCC")
    }

    // MARK: - Light or dark

    /// The window chrome follows the background: a dark scheme gets a dark
    /// border and a light cursor. Judging that wrong is the "washed-out theme"
    /// people report, with pale text on pale chrome.
    func testLightnessFollowsTheBackgroundBrightness() {
        XCTAssertFalse(TerminalTheme.isLight(background: "#000000"))
        XCTAssertFalse(TerminalTheme.isLight(background: "#0B1410"))
        XCTAssertFalse(TerminalTheme.isLight(background: "#808080"))

        XCTAssertTrue(TerminalTheme.isLight(background: "#BCBCBC"))
        XCTAssertTrue(TerminalTheme.isLight(background: "#FFFFFF"))
    }

    /// The switch is at 0.5 WCAG luminance and borrowed themes land right on it,
    /// so the two greys one step apart have to fall either side. A comparison
    /// that drifted to `>=` or that used a plain average would flip every scheme
    /// in that band and give them the wrong chrome.
    func testLightnessSwitchesExactlyAtTheHalfLuminanceBoundary() {
        XCTAssertFalse(TerminalTheme.isLight(background: "#BBBBBB"))
        XCTAssertTrue(TerminalTheme.isLight(background: "#BCBCBC"))
    }

    /// A colour that cannot be parsed is drawn as black (see `NSColor(hex:)`), so
    /// it has to be *judged* as black too. Otherwise a themed window ends up with
    /// light chrome around a black background.
    func testMalformedBackgroundIsJudgedAsBlack() {
        for malformed in ["", "nonsense", "#12345", "#GGGGGG"] {
            XCTAssertFalse(TerminalTheme.isLight(background: malformed), "\(malformed)")
        }

        let theme = terminalTheme(from: ParsedScheme(
            name: "Broken",
            background: "not-a-colour",
            foreground: "#FFFFFF",
            cursor: "#FFFFFF",
            ansi: Array(repeating: "#000000", count: 16),
            cursorIsFallback: false
        ))
        XCTAssertFalse(theme.isLight)
    }

    /// The two signature themes are the ones most people ever see, so they have to
    /// be on the right sides of the boundary: Guac dark, Guac Light light.
    func testSignatureThemesAreJudgedDarkAndLight() {
        XCTAssertFalse(TerminalTheme.guac.isLight)
        XCTAssertTrue(TerminalTheme.guacLight.isLight)
    }

    /// `isLight` is derived from the background rather than stored, and this is
    /// the regression that matters: the same scheme imported from a file must be
    /// judged exactly like its bundled twin, or the picker shows one chrome for
    /// the catalog entry and another for the copy the user made of it.
    func testASchemeRoundTrippedThroughTheImporterIsJudgedLikeItsBundledTwin() throws {
        let lightTheme = try XCTUnwrap(ThemeCatalogLoader.themes.first { $0.isLight })
        let darkTheme = try XCTUnwrap(ThemeCatalogLoader.themes.first { !$0.isLight })

        for theme in [lightTheme, darkTheme] {
            let scheme = try ITermColors.parse(terminalThemeSchemeFile(for: theme), name: theme.name)
            let imported = terminalTheme(from: scheme)

            XCTAssertFalse(scheme.cursorIsFallback, "\(theme.name) lost its cursor on the way through")
            XCTAssertEqual(imported.background, theme.background, theme.name)
            XCTAssertEqual(imported.foreground, theme.foreground, theme.name)
            XCTAssertEqual(imported.cursor, theme.cursor, theme.name)
            XCTAssertEqual(imported.ansi, theme.ansi, theme.name)
            XCTAssertEqual(imported.isLight, theme.isLight, theme.name)

            // Every colour survives untouched, and the only thing that differs is
            // the identifier, which the catalog assigns rather than the file.
            let rebuilt = terminalTheme(from: scheme, id: theme.id)
            XCTAssertEqual(rebuilt, theme, "\(theme.name) should survive the round trip unchanged")
        }
    }

    // MARK: - Drawing a colour

    /// Colours are saved, compared and shown as hex, so the conversion has to be
    /// lossless in both directions: a colour that drifts by one step every time
    /// it is read back would make every dark theme slightly grayer on relaunch.
    func testHexStringRoundTripsSixDigitColours() {
        for hex in ["#000000", "#102030", "#AABBCC", "#FFFFFF", "#0B1410", "#F7F4EA"] {
            XCTAssertEqual(NSColor(hex: hex).hexString, hex)
        }
    }

    /// Every colour the app ships or imports survives that round trip, since the
    /// picker's swatches and the terminal itself read them back through
    /// `NSColor(hex:)`. One entry that does not round trip is a swatch that does
    /// not match the terminal next to it.
    func testEveryCatalogColourRoundTripsThroughNSColor() {
        for theme in TerminalTheme.catalog {
            var colours = [theme.background, theme.foreground, theme.cursor]
            colours.append(contentsOf: theme.ansi)
            for hex in colours {
                XCTAssertEqual(NSColor(hex: hex).hexString, hex, "\(theme.id)")
            }
        }
    }

    /// `NSColor(hex:)` takes the three-digit form too, and `#ABC` is spelled out
    /// to `#AABBCC` rather than padded with zeros — the same expansion CSS and
    /// every other colour tool does.
    func testThreeDigitColourExpandsToSixDigits() {
        XCTAssertEqual(NSColor(hex: "#ABC").hexString, "#AABBCC")
        XCTAssertEqual(NSColor(hex: "ABC").hexString, "#AABBCC")
        XCTAssertEqual(NSColor(hex: "#FFF").hexString, "#FFFFFF")
    }

    /// A colour that cannot be read becomes black instead of crashing or drawing
    /// something random, which is what lets the app keep working with a
    /// hand-edited file in its library.
    func testUnreadableColourBecomesBlack() {
        for unreadable in ["", "not-a-colour", "#12345", "#1234567", "#GGGGGG", "#"] {
            XCTAssertEqual(NSColor(hex: unreadable).hexString, "#000000", "\(unreadable)")
        }
    }

    /// A channel built from something other than exact eighths is never quite the
    /// integer it stands for, and printing it has to round rather than truncate.
    /// A swatch one step darker than the terminal colour is exactly the kind of
    /// "the preview lies" report that comes in with imported schemes.
    func testChannelValuesOffByARoundingErrorStillPrintTheSameHex() {
        let almost = NSColor(
            srgbRed: CGFloat(0x1A) / 255 + 0.001,
            green: CGFloat(0x2B) / 255 - 0.001,
            blue: CGFloat(0x3C) / 255 + 0.001,
            alpha: 1
        )

        XCTAssertEqual(almost.hexString, "#1A2B3C")
    }

    // MARK: - The palette handed to SwiftTerm

    /// SwiftTerm takes the palette as a flat 16-colour array in ANSI order, so a
    /// slot out of place swaps red and green in every program the user runs. The
    /// terminal also receives the colours through `SwiftTerm.Color`, and those
    /// have to draw the same hex the theme names.
    func testPalettesHoldSixteenColoursInAnsiOrder() {
        for theme in [TerminalTheme.guac, TerminalTheme.guacLight] {
            XCTAssertEqual(theme.ansi.count, 16, theme.id)
            XCTAssertEqual(theme.nsAnsi.count, 16, theme.id)
            XCTAssertEqual(theme.terminalPalette.count, 16, theme.id)

            for (slot, expected) in theme.ansi.enumerated() {
                XCTAssertEqual(theme.nsAnsi[slot].hexString, expected, "\(theme.id) ANSI \(slot)")
                XCTAssertEqual(theme.terminalPalette[slot].nsColor.hexString, expected, "\(theme.id) ANSI \(slot)")
            }
        }
    }
}
