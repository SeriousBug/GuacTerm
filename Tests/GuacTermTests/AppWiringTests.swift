@testable import GuacTerm
import XCTest

/// The wiring between the pieces: settings in, a panel out, and a theme that
/// came from a file behaving exactly like one that shipped in the bundle.
///
/// Most of the app's bugs have lived on these seams rather than inside any one
/// file — a slider that changed a number nobody watched, an imported scheme that
/// got the chrome of a different colour — so they are tested as seams: build the
/// real objects, connect them the way the app does, and look at the result.
@MainActor
final class AppWiringTests: XCTestCase {
    /// Runs `body` with a `Settings` whose defaults domain belongs to the test.
    ///
    /// Nothing has to be undone afterwards: a settings model registers itself
    /// for theme changes and gives the registration back when it goes away, so
    /// a run leaves ``ThemeLibrary/shared`` as it found it.
    private func withSettings<T>(from defaults: TemporaryDefaults, _ body: (Settings) throws -> T) rethrows -> T {
        try body(Settings(defaults: defaults.defaults))
    }

    /// A model that is thrown away has to withdraw its registration. Without
    /// that, every model ever built — the app's own, and any a test or a future
    /// preview makes — stays in the library's list for the life of the process,
    /// being called into a `self` that no longer exists.
    func testASettingsModelWithdrawsItsThemeRegistrationWhenItGoesAway() throws {
        let library = ThemeLibrary.shared
        let before = library.changeHandlerCount

        try withSettings(from: TemporaryDefaults()) { _ in
            XCTAssertEqual(library.changeHandlerCount, before + 1)
        }

        XCTAssertEqual(library.changeHandlerCount, before)
    }

    /// A theme library over a directory of its own, so a test that imports or
    /// deletes a scheme never touches the schemes a person actually uses.
    private func makeLibrary(in directory: TemporaryDirectory) -> ThemeLibrary {
        ThemeLibrary(directory: directory.url)
    }

    // MARK: - The panel comes up from the settings

    /// Opening the app must not start a shell, animate a window or spawn
    /// anything: the panel is built and laid out in advance, and left off screen
    /// until the shortcut is pressed. A controller that says it is shown here is
    /// a terminal that typed itself into being at launch.
    func testBuildingAControllerLeavesThePanelOffScreen() throws {
        let defaults = try TemporaryDefaults()
        withSettings(from: defaults) { settings in
            let controller = TerminalController(settings: settings)

            XCTAssertFalse(controller.isShown)
            XCTAssertNil(controller.frameOnScreen)
        }
    }

    /// The settings pane is also the live preview, and that works only because
    /// the controller takes over the callbacks that redraw the terminal and
    /// resize the window. Something that reinstalls its own after the controller
    /// exists would break the preview without breaking the build.
    func testBuildingAControllerTakesOverTheCallbacksThatKeepThePreviewLive() throws {
        let defaults = try TemporaryDefaults()
        withSettings(from: defaults) { settings in
            var appearanceFired = false
            var sessionFired = false
            var geometryFired = false

            settings.onAppearanceChange = { appearanceFired = true }
            settings.onSessionSettingsChange = { sessionFired = true }
            settings.onWindowGeometryChange = { geometryFired = true }

            _ = TerminalController(settings: settings)

            // Assigning a setting fires its callback, so a callback that is
            // still the placeholder above did not get replaced.
            settings.darkThemeID = settings.darkThemeID
            XCTAssertFalse(appearanceFired, "the controller should be the one repainting on an appearance change")

            settings.shellPath = settings.shellPath
            XCTAssertFalse(sessionFired, "the controller should be the one noticing a new session is needed")

            settings.heightFraction = settings.heightFraction
            XCTAssertFalse(geometryFired, "the controller should be the one following the height slider")
        }
    }

    // MARK: - Imported themes

    /// A scheme imported from an `.itermcolors` file has to end up
    /// indistinguishable from the copy of the same colours that ships in the
    /// bundle — same sixteen ANSI slots, same chrome decision — because both go
    /// through the same parser. When they drifted, an imported light scheme came
    /// with dark window furniture and unreadable text.
    func testAnImportedSchemeIsIndistinguishableFromABundledOneWithTheSameBackground() throws {
        let directory = try TemporaryDirectory()

        // One dark scheme and one light one, so both judgements of "is this a
        // light theme" are compared, not just the one that is easy to get right.
        let sources = [TerminalTheme.guac, TerminalTheme.guacLight]
        let fileNames = try sources.map { bundled -> String in
            let fileName = "\(bundled.name) Copy.itermcolors"
            try directory.writeScheme(named: fileName, background: bundled.background)
            return fileName
        }

        // The parser on its own first: this is the code an import runs.
        let parsed = try ITermColors.parse(contentsOf: directory.url.appendingPathComponent(fileNames[0]))
        XCTAssertEqual(parsed.ansi.count, 16)

        let library = makeLibrary(in: directory)
        XCTAssertEqual(library.imported.count, sources.count)

        for (bundled, fileName) in zip(sources, fileNames) {
            let stem = (fileName as NSString).deletingPathExtension
            let imported = try XCTUnwrap(
                library.imported.first { $0.name == stem },
                "\(stem) should have been read into the library"
            )

            XCTAssertEqual(imported.id, ThemeLibrary.importedID(for: stem))
            XCTAssertTrue(library.isImported(imported))
            XCTAssertEqual(library.fileURL(for: imported)?.lastPathComponent, fileName)

            // Sixteen slots is what `installColors(_:)` is handed; anything
            // shorter leaves part of the palette drawing in defaults nobody
            // chose. Every entry also has to be a colour the app can parse.
            XCTAssertEqual(imported.ansi.count, 16)
            XCTAssertEqual(imported.terminalPalette.count, 16)
            for hex in imported.ansi + [imported.background, imported.foreground, imported.cursor] {
                XCTAssertTrue(TerminalTheme.isHexColor(hex), "\(hex) is not a colour")
            }

            XCTAssertEqual(imported.background, bundled.background)
            XCTAssertEqual(
                imported.isLight,
                bundled.isLight,
                "\(stem) has the same background as \(bundled.name) and must get the same chrome"
            )
        }
    }

    /// Deleting a theme's file in the Finder is how people change their mind
    /// about a scheme, and the app can only notice when it next reads the
    /// directory. It has to fall back to a theme that still exists: a selection
    /// pointing at nothing opens a terminal with no background and no palette.
    func testDeletingTheSelectedThemesFileFallsBackToTheDefaultTheme() throws {
        let directory = try TemporaryDirectory()
        try directory.writeScheme(named: "Doomed", background: "#123456")
        let library = makeLibrary(in: directory)

        let doomedID = ThemeLibrary.importedID(for: "Doomed")
        XCTAssertEqual(
            library.theme(id: doomedID).id,
            doomedID,
            "the scheme should be available to begin with"
        )

        // The file goes away behind the app's back, and the next import is what
        // makes the library read the directory again.
        try FileManager.default.removeItem(at: directory.url.appendingPathComponent("Doomed.itermcolors"))
        let staging = try TemporaryDirectory()
        try library.importThemes(from: [staging.writeScheme(named: "Newcomer", background: "#654321")])

        XCTAssertFalse(library.imported.contains { $0.id == doomedID })

        let fallback = library.theme(id: doomedID)
        XCTAssertEqual(fallback.id, TerminalTheme.defaultThemeID)
        XCTAssertEqual(fallback.name, TerminalTheme.guac.name)
        XCTAssertEqual(fallback.ansi.count, 16)
        XCTAssertNil(library.fileURL(for: fallback))
    }

    // MARK: - The selection

    /// What the terminal paints itself with comes from the selected identifier
    /// resolved through the real library, not from a copy of the catalog held
    /// somewhere else. With nothing configured that has to be the guac theme in
    /// dark mode and its daylight counterpart in light mode, or a first launch
    /// opens a terminal in colours nobody chose.
    func testOutOfTheBoxTheSelectionIsTheGuacTheme() throws {
        let defaults = try TemporaryDefaults()
        withSettings(from: defaults) { settings in
            XCTAssertEqual(settings.darkThemeID, TerminalTheme.defaultThemeID)
            XCTAssertEqual(settings.lightThemeID, TerminalTheme.defaultLightThemeID)

            settings.appearanceMode = .dark
            XCTAssertEqual(settings.theme.id, TerminalTheme.guac.id)
            XCTAssertEqual(settings.theme.name, TerminalTheme.guac.name)
            XCTAssertEqual(settings.theme.background, TerminalTheme.guac.background)
            XCTAssertEqual(settings.theme.ansi.count, 16)

            settings.appearanceMode = .light
            XCTAssertEqual(settings.theme.id, TerminalTheme.guacLight.id)
            XCTAssertEqual(settings.theme.ansi.count, 16)
        }
    }
}
