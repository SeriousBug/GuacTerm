@testable import GuacTerm
import XCTest

/// The schemes people bring with them from iTerm2. Everything that goes wrong
/// here is silent: an imported file under an identifier that moved loses the
/// selection on relaunch, a broken file left in the library shows up in the
/// picker as a theme with no colours, and an identifier that collides with a
/// bundled scheme hides one of the two. Every library here gets a directory of
/// its own under the system temporary directory, never the real one.
@MainActor
final class ThemeLibraryTests: XCTestCase {
    /// A theme that stands in for one of the bundled catalog entries, so a test
    /// does not depend on what ships in Resources/Themes.json.
    private func themeLibraryBundledTheme(id: String, name: String? = nil) -> TerminalTheme {
        TerminalTheme(
            id: id,
            name: name ?? id,
            background: "#000000",
            foreground: "#FFFFFF",
            cursor: "#FFFFFF",
            ansi: Array(repeating: "#808080", count: 16)
        )
    }

    /// The `.itermcolors` files in a directory, as an import panel would hand
    /// them over.
    private func themeLibraryFileURLs(in directory: TemporaryDirectory) throws -> [URL] {
        try directory.contents().map { directory.url.appendingPathComponent($0) }
    }

    /// A scheme with one ANSI slot left out, which is what a file written by a
    /// tool that stops at ANSI 15 looks like. `ThemePlist.scheme(ansi:)` numbers
    /// its keys by position, so the slot has to be dropped from the property
    /// list itself.
    private func themeLibrarySchemeWithoutAnsiThree() -> Data {
        var plist: [String: Any] = [:]
        for slot in 0 ..< 16 where slot != 3 {
            plist["Ansi \(slot) Color"] = ThemePlist.component(Double(slot) / 16)
        }
        plist["Background Color"] = ThemePlist.color(from: "#101010")
        plist["Foreground Color"] = ThemePlist.color(from: "#EEEEEE")
        plist["Cursor Color"] = ThemePlist.color(from: "#FFFFFF")
        return ThemePlist.serialized(plist)
    }

    /// A directory with a valid scheme and garbage in it: the first file is
    /// imported when only the good ones are expected to survive.
    private func themeLibraryMixedFolder() throws -> TemporaryDirectory {
        let source = try TemporaryDirectory()
        try source.writeScheme(named: "Good")
        try source.write(themeLibrarySchemeWithoutAnsiThree(), as: "Bad.itermcolors")
        try source.write(Data("just some notes".utf8), as: "readme.txt")
        return source
    }

    /// Two files in, two schemes out: listed by name, identified by prefix and
    /// slug, and pointing at a file inside the library rather than at wherever
    /// they were imported from. The repaint callback firing once is what makes
    /// the picker show the colours that just arrived.
    func testImportingTwoSchemesListsThemWithStablePrefixedIds() throws {
        let source = try TemporaryDirectory()
        try source.writeScheme(named: "Zebra")
        try source.writeScheme(named: "Solarized Dark")

        let destination = try TemporaryDirectory()
        let bundled = [themeLibraryBundledTheme(id: "guac")]
        let themes = ThemeLibrary(bundled: bundled, directory: destination.url)
        var repaints = 0
        themes.onChange { repaints += 1 }

        let summary = try themes.importThemes(from: themeLibraryFileURLs(in: source))

        XCTAssertTrue(summary.failures.isEmpty)
        XCTAssertEqual(themes.imported.map(\.name), ["Solarized Dark", "Zebra"])
        XCTAssertEqual(
            themes.imported.map(\.id),
            ["imported-solarized-dark-1m1k", "imported-zebra-331r"]
        )
        XCTAssertEqual(
            summary.importedIDs.sorted(),
            ["imported-solarized-dark-1m1k", "imported-zebra-331r"]
        )
        XCTAssertEqual(summary.firstImportedID, "imported-solarized-dark-1m1k")
        XCTAssertEqual(summary.message, "Imported 2 themes.")
        XCTAssertEqual(repaints, 1)
        XCTAssertEqual(themes.all, themes.imported + bundled)
        XCTAssertEqual(try destination.contents(), ["Solarized Dark.itermcolors", "Zebra.itermcolors"])

        for theme in themes.imported {
            let url = try XCTUnwrap(themes.fileURL(for: theme))
            XCTAssertEqual(
                url.resolvingSymlinksInPath().deletingLastPathComponent().path,
                destination.url.resolvingSymlinksInPath().path
            )
            XCTAssertTrue(themes.isImported(theme))
        }
        XCTAssertFalse(themes.isImported(bundled[0]))
        XCTAssertNil(themes.fileURL(for: bundled[0]))
    }

    /// A file that is not an iTerm2 scheme is refused before anything is copied,
    /// so the library never collects files the picker cannot draw.
    func testANonItermFileIsRefusedAndNothingIsCopied() throws {
        let source = try TemporaryDirectory()
        try source.write(Data("not a scheme".utf8), as: "notes.txt")

        let destination = try TemporaryDirectory()
        let themes = ThemeLibrary(bundled: [], directory: destination.url)
        var repaints = 0
        themes.onChange { repaints += 1 }

        let summary = try themes.importThemes(from: themeLibraryFileURLs(in: source))

        XCTAssertEqual(summary.failures.count, 1)
        XCTAssertEqual(summary.failures.first?.file, "notes.txt")
        XCTAssertEqual(summary.failures.first?.reason, "not an .itermcolors file")
        XCTAssertNil(summary.firstImportedID)
        XCTAssertTrue(summary.importedIDs.isEmpty)
        XCTAssertTrue(summary.message.hasPrefix("Nothing imported."))
        XCTAssertEqual(repaints, 0)
        XCTAssertTrue(themes.imported.isEmpty)
        XCTAssertEqual(try destination.contents(), [])
    }

    /// A scheme the parser rejects is reported with the parser's own words —
    /// naming the missing colour is the only way the user can fix the file —
    /// and it is not left behind in the library.
    func testABrokenSchemeIsReportedWithTheParsersReasonAndNotKept() throws {
        let source = try TemporaryDirectory()
        try source.write(themeLibrarySchemeWithoutAnsiThree(), as: "Broken.itermcolors")

        let destination = try TemporaryDirectory()
        let themes = ThemeLibrary(bundled: [], directory: destination.url)

        let summary = try themes.importThemes(from: themeLibraryFileURLs(in: source))

        XCTAssertEqual(summary.failures.map(\.file), ["Broken.itermcolors"])
        XCTAssertEqual(summary.failures.first?.reason, "no Ansi 3 Color")
        XCTAssertTrue(summary.message.contains("no Ansi 3 Color"))
        XCTAssertNil(summary.firstImportedID)
        XCTAssertTrue(themes.imported.isEmpty)
        XCTAssertEqual(try destination.contents(), [])
    }

    /// Dropping a whole folder on the app imports what it can and says what it
    /// could not, rather than refusing all of it because one file was broken.
    func testImportingAFolderKeepsTheGoodSchemesAndReportsTheRest() throws {
        let source = try themeLibraryMixedFolder()

        let destination = try TemporaryDirectory()
        let themes = ThemeLibrary(bundled: [], directory: destination.url)

        let summary = try themes.importThemes(from: themeLibraryFileURLs(in: source))

        XCTAssertEqual(summary.importedNames, ["Good"])
        XCTAssertEqual(summary.importedIDs, ["imported-good-3t2w"])
        XCTAssertEqual(summary.failures.count, 2)
        XCTAssertEqual(Set(summary.failures.map(\.file)), ["Bad.itermcolors", "readme.txt"])
        XCTAssertEqual(themes.imported.map(\.name), ["Good"])
        XCTAssertEqual(try destination.contents(), ["Good.itermcolors"])
        XCTAssertTrue(summary.message.hasPrefix("Imported Good; skipped "))
    }

    /// Importing a corrected copy of a scheme the user already has must replace
    /// it — one entry, the new colours — because duplicating it would leave the
    /// picker showing the old colours next to the new ones.
    func testReimportingTheSameFilenameReplacesTheScheme() throws {
        let source = try TemporaryDirectory()
        try source.writeScheme(named: "Nord", background: "#101010")

        let destination = try TemporaryDirectory()
        let themes = ThemeLibrary(bundled: [], directory: destination.url)
        try themes.importThemes(from: themeLibraryFileURLs(in: source))
        XCTAssertEqual(themes.imported.map(\.background), ["#101010"])

        try source.writeScheme(named: "Nord", background: "#203040")
        try themes.importThemes(from: themeLibraryFileURLs(in: source))

        XCTAssertEqual(themes.imported.count, 1)
        XCTAssertEqual(themes.imported.map(\.id), ["imported-nord-ezbo"])
        XCTAssertEqual(themes.imported.map(\.background), ["#203040"])
        XCTAssertEqual(try destination.contents(), ["Nord.itermcolors"])
    }

    /// `Solarized Dark` and `Solarized-Dark` slug to the same identifier, and
    /// are two schemes, not one. The digest of the name is what keeps them
    /// apart: a shared slug alone would have made one of them the other's
    /// duplicate, and a fresh library reading the same directory has to give
    /// the same pair again or the selected theme changes by itself the next
    /// time the app starts.
    func testSchemesWhoseNamesSlugAlikeStillGetTheirOwnIdentifier() throws {
        let destination = try TemporaryDirectory()
        try destination.writeScheme(named: "Solarized Dark")
        try destination.writeScheme(named: "Solarized-Dark")

        let first = ThemeLibrary(bundled: [], directory: destination.url)
        let assignment = Dictionary(uniqueKeysWithValues: first.imported.map { ($0.name, $0.id) })

        XCTAssertEqual(assignment, [
            "Solarized Dark": "imported-solarized-dark-1m1k",
            "Solarized-Dark": "imported-solarized-dark-vm2r",
        ])
        XCTAssertEqual(first.imported.count, 2)
        XCTAssertEqual(Set(first.imported.map(\.id)).count, 2)
        XCTAssertEqual(first.imported.map(\.id), first.imported.map { ThemeLibrary.importedID(for: $0.name) })

        let second = ThemeLibrary(bundled: [], directory: destination.url)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: second.imported.map { ($0.name, $0.id) }), assignment)
        XCTAssertEqual(first.fileURL(for: first.imported[0]), second.fileURL(for: second.imported[0]))
    }

    /// The identifier is what `UserDefaults` remembers, so changing how one is
    /// made costs every user their selected imported theme once: it resolves to
    /// the default instead. These strings are therefore a compatibility
    /// promise, and a test that has to be edited is the reminder that the
    /// promise is being broken.
    func testTheIdentifierOfAKnownSchemeDoesNotDrift() {
        XCTAssertEqual(ThemeLibrary.importedID(for: "Nord"), "imported-nord-ezbo")
        XCTAssertEqual(ThemeLibrary.importedID(for: "Solarized Dark"), "imported-solarized-dark-1m1k")
        XCTAssertEqual(ThemeLibrary.importedID(for: "Gruvbox-Dark (Hard)"), "imported-gruvbox-dark-hard-50k1")
    }

    /// A scheme called in a script with no ASCII letters has nothing left to
    /// slug, and used to end up as the bare prefix — an identifier with no name
    /// in it, and the same one for every such file. The digest is what it gets
    /// instead, so two of them stay two themes.
    func testANameWithNoASCIILettersStillGetsItsOwnIdentifier() throws {
        XCTAssertEqual(ThemeLibrary.importedID(for: "日本語"), "imported-9zaf")
        XCTAssertTrue(ThemeLibrary.importedID(for: "日本語").hasPrefix(ThemeLibrary.importedIDPrefix))

        let destination = try TemporaryDirectory()
        try destination.writeScheme(named: "日本語")
        try destination.writeScheme(named: "★★★")

        let themes = ThemeLibrary(bundled: [], directory: destination.url)

        XCTAssertEqual(themes.imported.count, 2)
        // Listed by name, which is why the stars come first.
        XCTAssertEqual(themes.imported.map(\.id), ["imported-fp84", "imported-9zaf"])
        XCTAssertEqual(themes.imported.map(\.name), ["★★★", "日本語"])
        XCTAssertNotEqual(themes.imported[0].id, ThemeLibrary.importedIDPrefix)
        XCTAssertEqual(Set(themes.imported.map(\.id)).count, 2)
    }

    /// Two observers are the normal case: the settings model repaints the
    /// terminal, and anything else watching — a preview, a second window — wants
    /// the same news. Whichever registered last used to be the only one that
    /// heard about an import.
    func testEveryRegisteredObserverHearsAboutAnImport() throws {
        let source = try TemporaryDirectory()
        try source.writeScheme(named: "Nord")
        let themes = try ThemeLibrary(bundled: [], directory: TemporaryDirectory().url)

        var firstHeard = 0
        var secondHeard = 0
        themes.onChange { firstHeard += 1 }
        themes.onChange { secondHeard += 1 }
        XCTAssertEqual(themes.changeHandlerCount, 2)

        try themes.importThemes(from: themeLibraryFileURLs(in: source))

        XCTAssertEqual(firstHeard, 1)
        XCTAssertEqual(secondHeard, 1)
    }

    /// Withdrawing a registration has to leave the others alone: the observer
    /// that is still there is the one that repaints the terminal.
    func testAWithdrawnObserverStopsHearing() throws {
        let source = try TemporaryDirectory()
        try source.writeScheme(named: "Nord")
        let themes = try ThemeLibrary(bundled: [], directory: TemporaryDirectory().url)

        var keptHeard = 0
        var withdrawnHeard = 0
        themes.onChange { keptHeard += 1 }
        let token = themes.onChange { withdrawnHeard += 1 }

        themes.removeOnChange(token)
        XCTAssertEqual(themes.changeHandlerCount, 1)

        try themes.importThemes(from: themeLibraryFileURLs(in: source))

        XCTAssertEqual(keptHeard, 1)
        XCTAssertEqual(withdrawnHeard, 0)
    }

    /// Importing a scheme named like a bundled one keeps both: the imported file
    /// gets the prefix, so neither hides the other and the identifier stored in
    /// the defaults still means what it meant.
    func testAnImportedSchemeNeverShadowsABundledOne() throws {
        let destination = try TemporaryDirectory()
        try destination.writeScheme(named: "Nord")

        let bundled = [themeLibraryBundledTheme(id: "nord", name: "Nord")]
        let themes = ThemeLibrary(bundled: bundled, directory: destination.url)

        XCTAssertEqual(themes.imported.map(\.id), ["imported-nord-ezbo"])
        XCTAssertEqual(themes.all.map(\.id), ["imported-nord-ezbo", "nord"])
        XCTAssertEqual(themes.theme(id: "nord"), bundled[0])
        XCTAssertFalse(themes.isImported(themes.theme(id: "nord")))
        XCTAssertTrue(themes.isImported(themes.theme(id: "imported-nord-ezbo")))
        XCTAssertEqual(themes.theme(id: "imported-nord-ezbo").name, "Nord")
    }

    /// An identifier whose theme is gone — an older version's, or an imported
    /// file the user trashed — must fall back to a usable theme rather than to
    /// whichever scheme happens to sort first, and never crash.
    func testAnUnknownIdentifierFallsBackToTheDefaultTheme() throws {
        let destination = try TemporaryDirectory()
        let bundled = [themeLibraryBundledTheme(id: "custom", name: "Custom")]

        let themes = ThemeLibrary(bundled: bundled, directory: destination.url)
        XCTAssertEqual(themes.theme(id: "no-such-theme"), bundled[0])

        let withoutCatalog = ThemeLibrary(bundled: [], directory: destination.url)
        let fallback = withoutCatalog.theme(id: "no-such-theme")
        XCTAssertEqual(fallback.id, TerminalTheme.defaultThemeID)
        XCTAssertEqual(fallback, TerminalTheme.guac)
        XCTAssertEqual(fallback.ansi.count, 16)
    }

    /// A bundled scheme is not the user's file to lose: removing one has to do
    /// nothing at all, and must not repaint or restart anything.
    func testRemovingABundledThemeIsRefusedAndTouchesNoFile() throws {
        let destination = try TemporaryDirectory()
        try destination.writeScheme(named: "Kept")

        let bundled = [themeLibraryBundledTheme(id: "kept-bundled", name: "Kept Bundled")]
        let themes = ThemeLibrary(bundled: bundled, directory: destination.url)
        var repaints = 0
        themes.onChange { repaints += 1 }

        XCTAssertFalse(themes.remove(bundled[0]))
        XCTAssertFalse(themes.remove(themes.theme(id: "kept-bundled")))
        XCTAssertEqual(repaints, 0)
        XCTAssertEqual(themes.all.count, 2)
        XCTAssertEqual(try destination.contents(), ["Kept.itermcolors"])
    }

    /// Removing an imported scheme takes it out of the picker and moves its file
    /// out of the library — to the Trash, which is why this only ever touches a
    /// file inside the test's own directory.
    func testRemovingAnImportedThemeTakesItOutOfThePicker() throws {
        let source = try TemporaryDirectory()
        try source.writeScheme(named: "Gone")

        let destination = try TemporaryDirectory()
        let themes = ThemeLibrary(bundled: [], directory: destination.url)
        try themes.importThemes(from: themeLibraryFileURLs(in: source))
        let importedTheme = try XCTUnwrap(themes.imported.first)

        var repaints = 0
        themes.onChange { repaints += 1 }
        XCTAssertTrue(themes.remove(importedTheme))

        XCTAssertEqual(repaints, 1)
        XCTAssertTrue(themes.imported.isEmpty)
        XCTAssertTrue(themes.all.isEmpty)
        XCTAssertNil(themes.fileURL(for: importedTheme))
        XCTAssertEqual(themes.theme(id: importedTheme.id).id, TerminalTheme.defaultThemeID)
        XCTAssertEqual(try destination.contents(), [])
    }

    /// A file that was already broken on disk — hand-edited, half-copied, from a
    /// tool that writes another format — is skipped at load so the picker opens
    /// on the schemes that do work.
    func testAMalformedFileAlreadyInTheLibraryIsSkippedOnLoad() throws {
        let destination = try TemporaryDirectory()
        try destination.write(Data("this is not a property list".utf8), as: "Junk.itermcolors")
        try destination.writeScheme(named: "Fine")

        let themes = ThemeLibrary(bundled: [], directory: destination.url)

        XCTAssertEqual(themes.imported.map(\.name), ["Fine"])
        XCTAssertEqual(themes.imported.map(\.id), ["imported-fine-ewp9"])
        // Skipped, not deleted: the user still has the file to fix or remove.
        XCTAssertEqual(try destination.contents(), ["Fine.itermcolors", "Junk.itermcolors"])
    }
}
