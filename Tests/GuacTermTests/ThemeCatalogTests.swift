import Foundation
@testable import GuacTerm
import XCTest

/// The picker offers around 890 vendored schemes, and every one of them has to be
/// drawable from the moment the app opens: one bad entry is a theme with an
/// invisible cursor, a washed-out palette or a preview that draws nothing. These
/// tests check the shipped resource the user actually gets, not a fixture.
final class ThemeCatalogTests: XCTestCase {
    // MARK: - Fixtures

    /// The bundled Themes.json, decoded but not yet filtered, so a test can tell
    /// what the app shipped apart from what the loader was willing to keep.
    private func catalogBundledJSON() throws -> [[String: Any]] {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "Themes", withExtension: "json"),
            "Themes.json is missing from the app bundle"
        )
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(json as? [[String: Any]], "Themes.json is not an array of objects")
    }

    /// Stands in for a theme when only the ordering rule is under test, which is
    /// the one place a theme's colours do not matter.
    private struct CatalogSortingStub: NamedTheme {
        let id: String
        let name: String
    }

    // MARK: - The shipped resource

    /// The loader's contract with the generator: one object per scheme, with an
    /// identifier, a name and five colour fields. If the shape drifts, the app
    /// silently offers only its two signature themes, and this is the test that
    /// says so.
    func testBundledThemesFileHoldsOneObjectPerScheme() throws {
        let entries = try catalogBundledJSON()

        XCTAssertFalse(entries.isEmpty)
        XCTAssertEqual(entries.count, ThemeCatalogLoader.themes.count)

        for entry in entries {
            for key in ["id", "name", "bg", "fg", "cursor"] {
                XCTAssertTrue(entry[key] is String, "\(key) is not a string in \(entry)")
            }
            let ansi = try XCTUnwrap(entry["ansi"] as? [String], "ansi is not a list of strings in \(entry)")
            XCTAssertEqual(ansi.count, 16, "\(entry["name"] ?? "?")")
        }
    }

    /// A vendored theme is offered straight to the user, with no way to fix it, so
    /// every field has to be present and drawable: a name to show, sixteen ANSI
    /// colours, and hex the terminal can parse. The loader's guards exist for
    /// this; here they are checked against the real file.
    func testEveryVendoredThemeIsCompleteAndDrawable() {
        XCTAssertFalse(ThemeCatalogLoader.themes.isEmpty, "the vendored catalog failed to load")

        for theme in ThemeCatalogLoader.themes {
            XCTAssertFalse(theme.id.isEmpty)
            XCTAssertFalse(theme.name.isEmpty)
            XCTAssertEqual(theme.ansi.count, 16, "\(theme.id)")

            for hex in [theme.background, theme.foreground, theme.cursor] + theme.ansi {
                XCTAssertTrue(TerminalTheme.isHexColor(hex), "\(theme.id): \(hex) is not a colour")
            }
        }
    }

    /// Identifiers end up in `UserDefaults` and names are what the user reads, so
    /// two schemes sharing either one makes the picker show a duplicate and makes
    /// the saved selection ambiguous. Names are compared case-insensitively,
    /// because "Night" and "night" read as the same theme.
    func testVendoredThemesHaveDistinctIdentifiersAndNames() {
        let themes = ThemeCatalogLoader.themes

        XCTAssertEqual(Set(themes.map(\.id)).count, themes.count)
        XCTAssertEqual(Set(themes.map { $0.name.lowercased() }).count, themes.count)
    }

    /// The generator writes the file sorted by `NamedTheme.nameOrder` and the
    /// picker lists it as read, so the resource has to already be in that order —
    /// the sort is what makes a long list scannable and stable across releases.
    func testVendoredThemesAreSortedByTheNameOrderRule() {
        let themes = ThemeCatalogLoader.themes

        for (earlier, later) in zip(themes, themes.dropFirst()) {
            XCTAssertTrue(
                TerminalTheme.nameOrder(earlier, later),
                "\(earlier.name) (\(earlier.id)) should come before \(later.name) (\(later.id))"
            )
        }
    }

    /// The ordering rule has to be total, or the file the generator writes and the
    /// list the picker shows disagree about ties: the case of a name, or two
    /// schemes that differ only in identifier. It also has to be strict, so no
    /// element can be "less than" itself.
    func testNameOrderIsTotalWhenNamesCollide() {
        typealias Stub = CatalogSortingStub

        // Different names are ordered case-insensitively.
        XCTAssertTrue(Stub.nameOrder(Stub(id: "z", name: "apple"), Stub(id: "a", name: "Zebra")))
        XCTAssertFalse(Stub.nameOrder(Stub(id: "a", name: "Zebra"), Stub(id: "z", name: "apple")))

        // The same name in another case is broken by the exact name.
        XCTAssertTrue(Stub.nameOrder(Stub(id: "a", name: "ALPHA"), Stub(id: "b", name: "alpha")))
        XCTAssertFalse(Stub.nameOrder(Stub(id: "b", name: "alpha"), Stub(id: "a", name: "ALPHA")))

        // The same name is broken by the identifier.
        XCTAssertTrue(Stub.nameOrder(Stub(id: "a", name: "Same"), Stub(id: "b", name: "Same")))
        XCTAssertFalse(Stub.nameOrder(Stub(id: "b", name: "Same"), Stub(id: "a", name: "Same")))

        let only = Stub(id: "a", name: "Same")
        XCTAssertFalse(Stub.nameOrder(only, only))
    }

    // MARK: - The catalog the picker shows

    /// "guac" is the default theme and the fallback for a saved identifier that no
    /// longer resolves, so it has to be the first row of the picker: a user who
    /// never opened Settings should never have to scroll to find what they are
    /// looking at.
    func testCatalogPutsTheDefaultThemeFirst() {
        XCTAssertEqual(TerminalTheme.defaultThemeID, "guac")
        XCTAssertEqual(Array(TerminalTheme.catalog.prefix(2)).map(\.id), ["guac", "guac-light"])
        XCTAssertEqual(TerminalTheme.catalog.first, TerminalTheme.guac)
    }

    /// The catalog is the catalog, not a replacement: the two signature themes come
    /// first and every vendored scheme is appended behind them, unfiltered. A
    /// vendored scheme may not shadow a signature theme either, or "guac" would
    /// stop being the default and the picker would list the same theme twice.
    func testCatalogIsTheVendoredListBehindTheSignatureThemes() {
        let catalog = TerminalTheme.catalog
        let vendored = ThemeCatalogLoader.themes

        XCTAssertEqual(catalog.count, 2 + vendored.count)
        XCTAssertEqual(Array(catalog.dropFirst(2)), vendored)

        let signatureIDs = Set([TerminalTheme.guac.id, TerminalTheme.guacLight.id])
        let signatureNames = Set([TerminalTheme.guac.name.lowercased(), TerminalTheme.guacLight.name.lowercased()])
        for theme in vendored {
            XCTAssertFalse(signatureIDs.contains(theme.id), "\(theme.id) shadows a signature theme")
            XCTAssertFalse(signatureNames.contains(theme.name.lowercased()), "\(theme.name) shadows a signature theme")
        }

        XCTAssertEqual(Set(catalog.map(\.id)).count, catalog.count)
        XCTAssertEqual(Set(catalog.map { $0.name.lowercased() }).count, catalog.count)
    }

    // MARK: - A damaged resource

    /// One entry of Themes.json, spelled out, so a test can leave a piece out.
    private func catalogEntry(
        id: String = "nord",
        name: String = "Nord",
        background: String = "#2E3440",
        foreground: String = "#D8DEE9",
        cursor: String = "#D8DEE9",
        ansi: [String] = Array(repeating: "#4C566A", count: 16)
    ) -> [String: Any] {
        ["id": id, "name": name, "bg": background, "fg": foreground, "cursor": cursor, "ansi": ansi]
    }

    /// Runs the loader over entries as if they had been found in the resource.
    private func catalogThemes(from entries: [[String: Any]]) throws -> [TerminalTheme] {
        try ThemeCatalogLoader.themes(from: JSONSerialization.data(withJSONObject: entries))
    }

    /// The resource is read at launch, so anything it cannot understand has to
    /// cost the app its vendored schemes and nothing more. A throw here is a
    /// crash on every start, and there is no window yet to report it in.
    func testAResourceThatIsNotASchemeListLeavesNoThemes() {
        for data in [
            Data(),
            Data("not json at all".utf8),
            Data("{}".utf8),
            Data("[]".utf8),
            Data("[{\"id\":\"nord\"}]".utf8),
        ] {
            XCTAssertEqual(
                ThemeCatalogLoader.themes(from: data),
                [],
                "\(String(decoding: data, as: UTF8.self)) should read as no themes"
            )
        }
    }

    /// Half a scheme is not a scheme: the picker would offer a theme with a
    /// hole in its palette. Those entries are dropped and the complete ones
    /// beside them are kept, rather than the whole file being thrown away.
    func testSchemeWithSomethingMissingIsDroppedButTherestAreKept() throws {
        let themes = try catalogThemes(from: [
            catalogEntry(id: "short-palette", name: "Short", ansi: Array(repeating: "#4C566A", count: 15)),
            catalogEntry(id: "no-name", name: ""),
            catalogEntry(id: "", name: "No Identifier"),
            catalogEntry(id: "bad-background", name: "Bad Background", background: "not a colour"),
            catalogEntry(
                id: "bad-ansi",
                name: "Bad Ansi",
                ansi: ["#4C566A", "#GGGGGG"] + Array(repeating: "#4C566A", count: 14)
            ),
            catalogEntry(id: "fine", name: "Fine"),
        ])

        XCTAssertEqual(themes.map(\.id), ["fine"])
        XCTAssertEqual(themes.first?.ansi.count, 16)
    }

    /// Two entries sharing an identifier are one theme: the identifier is what
    /// `UserDefaults` stores, and two themes answering to it would make the
    /// selection mean whichever one the list happened to put first.
    func testTwoSchemesWithTheSameIdentifierBecomeOne() throws {
        let themes = try catalogThemes(from: [
            catalogEntry(id: "gruvbox", name: "Gruvbox"),
            catalogEntry(id: "gruvbox", name: "Gruvbox Again"),
        ])

        XCTAssertEqual(themes.map(\.name), ["Gruvbox"])
    }

    /// The order the file happens to be written in is not the order the picker
    /// shows: the list is sorted by the same rule the generator uses, so a
    /// regenerated resource does not reshuffle the picker.
    func testWhatTheLoaderReadsIsSortedByName() throws {
        let themes = try catalogThemes(from: [
            catalogEntry(id: "zebra", name: "Zebra"),
            catalogEntry(id: "apple", name: "apple"),
            catalogEntry(id: "nord", name: "Nord"),
        ])

        XCTAssertEqual(themes.map(\.name), ["apple", "Nord", "Zebra"])
    }

    /// The loader never throws: a missing or damaged Themes.json leaves two usable
    /// themes rather than an empty picker or a crash, so the app still works for
    /// someone who installed a build with the resource left out. Whatever the
    /// loader does, these two have to be complete on their own.
    func testSignatureThemesStayUsableWithoutTheVendoredCatalog() {
        for theme in [TerminalTheme.guac, TerminalTheme.guacLight] {
            XCTAssertFalse(theme.id.isEmpty)
            XCTAssertFalse(theme.name.isEmpty)
            XCTAssertEqual(theme.ansi.count, 16, theme.id)

            for hex in [theme.background, theme.foreground, theme.cursor] + theme.ansi {
                XCTAssertTrue(TerminalTheme.isHexColor(hex), "\(theme.id): \(hex) is not a colour")
            }
        }

        // Whatever the loader hands back, the merged catalog can only grow from
        // the two signature themes; an empty vendored list is a working app.
        XCTAssertGreaterThanOrEqual(TerminalTheme.catalog.count, 2)
    }
}
