import AppKit
import Carbon.HIToolbox
@testable import GuacTerm
import XCTest

/// Everything a person can change lives in this one object, and the panel, the
/// open window and a running session each learn about a change through a
/// callback of their own. These tests pin what a fresh install starts with, that
/// the whole set survives a relaunch, that yesterday's garbage in the defaults
/// domain is degraded rather than trusted, and that changing one setting does
/// not quietly redraw or restart something else.
@MainActor
final class SettingsTests: XCTestCase {
    /// A settings object on a defaults domain nothing else writes to, kept with
    /// the domain for as long as the test needs it: `TemporaryDefaults` wipes the
    /// domain when it goes away.
    private func makeSettingsSubject() throws -> (settings: Settings, domain: TemporaryDefaults) {
        let temp = try TemporaryDefaults()
        return (Settings(defaults: temp.defaults), temp)
    }

    /// The defaults keys are what a `defaults write` from a terminal hits, so a
    /// hand-edited domain is spelled out here rather than derived from anything
    /// private.
    private enum StoredKey {
        static let shortcut = "shortcut"
        static let shellPath = "shellPath"
        static let scrollbackLines = "scrollbackLines"
        static let darkThemeID = "darkThemeID"
        static let lightThemeID = "lightThemeID"
        static let legacyThemeID = "themeID"
        static let heightFraction = "heightFraction"
        static let fontName = "fontName"
        static let fontSize = "fontSize"
        static let hideOnFocusLoss = "hideOnFocusLoss"
        static let glassTint = "glassTint"
        static let legacyGlassBackground = "glassBackground"
        static let appearanceMode = "appearanceMode"
    }

    /// The first launch of the app: no window taller than asked for, no glass
    /// darker than asked for, a readable 13pt grid, the shortcut people are
    /// told about, and — when one is installed — a multiplexer as the shell,
    /// since tabs and splits are what people reach for tmux or zellij for.
    func testAFreshInstallStartsWithTheDocumentedDefaults() throws {
        let subject = try makeSettingsSubject()
        let settings = subject.settings

        XCTAssertEqual(settings.scrollbackLines, 10000)
        XCTAssertEqual(settings.heightFraction, 0.45, accuracy: 0.000_001)
        XCTAssertEqual(settings.fontSize, 13)
        XCTAssertEqual(settings.glassTint, 0.65, accuracy: 0.000_001)
        XCTAssertTrue(settings.hideOnFocusLoss)
        XCTAssertEqual(settings.darkThemeID, "guac")
        XCTAssertEqual(settings.darkThemeID, TerminalTheme.defaultThemeID)
        XCTAssertEqual(settings.lightThemeID, "guac-light")
        XCTAssertEqual(settings.lightThemeID, TerminalTheme.defaultLightThemeID)
        XCTAssertEqual(settings.shortcut, .default)
        XCTAssertEqual(settings.appearanceMode, .system)
        XCTAssertEqual(settings.shellPath, Settings.firstLaunchShell)
        XCTAssertEqual(settings.fontName, Settings.defaultFontName)
    }

    /// Quitting and starting again must give back exactly what was chosen,
    /// otherwise the settings window is lying about what the app will do.
    func testEverySettingComesBackAfterARelaunch() throws {
        let subject = try makeSettingsSubject()
        let settings = subject.settings

        let shortcut = KeyCombo(keyCode: UInt16(kVK_ANSI_J), carbonModifiers: UInt32(cmdKey | shiftKey))
        settings.shortcut = shortcut
        settings.shellPath = "/bin/sh"
        settings.scrollbackLines = 500
        settings.darkThemeID = "solarized-dark"
        settings.lightThemeID = "solarized-light"
        settings.heightFraction = 0.8
        settings.fontName = "Menlo"
        settings.fontSize = 15.5
        settings.hideOnFocusLoss = false
        settings.glassTint = 0.4
        settings.appearanceMode = .dark

        let relaunched = Settings(defaults: subject.domain.defaults)

        XCTAssertEqual(relaunched.shortcut, shortcut)
        XCTAssertEqual(relaunched.shellPath, "/bin/sh")
        XCTAssertEqual(relaunched.scrollbackLines, 500)
        XCTAssertEqual(relaunched.darkThemeID, "solarized-dark")
        XCTAssertEqual(relaunched.lightThemeID, "solarized-light")
        XCTAssertEqual(relaunched.heightFraction, 0.8, accuracy: 0.000_001)
        XCTAssertEqual(relaunched.fontName, "Menlo")
        XCTAssertEqual(relaunched.fontSize, 15.5)
        XCTAssertFalse(relaunched.hideOnFocusLoss)
        XCTAssertEqual(relaunched.glassTint, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(relaunched.appearanceMode, .dark)
    }

    /// A domain written by an older version, or by hand, must not stop the app
    /// from starting: an unreadable value falls back to what a fresh install
    /// would have used instead of trapping at launch.
    func testUnreadableStoredValuesFallBackToTheDefaults() throws {
        let temp = try TemporaryDefaults()
        temp.defaults.set("plaid", forKey: StoredKey.appearanceMode)
        temp.defaults.set(Data("this is not a key combo".utf8), forKey: StoredKey.shortcut)
        temp.defaults.set("not a number", forKey: StoredKey.scrollbackLines)

        let settings = Settings(defaults: temp.defaults)

        XCTAssertEqual(settings.appearanceMode, .system)
        XCTAssertEqual(settings.shortcut, .default)
        XCTAssertEqual(settings.scrollbackLines, 10000)
        XCTAssertEqual(settings.fontName, Settings.defaultFontName)
        XCTAssertEqual(settings.shellPath, Settings.firstLaunchShell)
    }

    /// A scrollback count stored as a fraction is not a count at all, so the
    /// default is used rather than a truncated number nobody typed.
    func testAFractionalScrollbackCountFallsBackToTheDefault() throws {
        let temp = try TemporaryDefaults()
        temp.defaults.set(5000.5, forKey: StoredKey.scrollbackLines)

        XCTAssertEqual(Settings(defaults: temp.defaults).scrollbackLines, 10000)
    }

    /// A hand-edited domain cannot reach the terminal with a number the sliders
    /// would refuse. The ceiling matters as much as the floor here: the
    /// scrollback count is handed to SwiftTerm, which reserves room for it, so
    /// an extra six digits is a memory cost at launch rather than a cosmetic
    /// one.
    func testHandEditedNumbersAreBroughtBackInsideTheirRange() throws {
        let tooLarge = try TemporaryDefaults()
        tooLarge.defaults.set(2_000_000, forKey: StoredKey.scrollbackLines)
        tooLarge.defaults.set(3.0, forKey: StoredKey.heightFraction)
        tooLarge.defaults.set(1000.0, forKey: StoredKey.fontSize)
        tooLarge.defaults.set(4.0, forKey: StoredKey.glassTint)

        let oversized = Settings(defaults: tooLarge.defaults)
        XCTAssertEqual(oversized.scrollbackLines, Settings.Limits.scrollback.upperBound)
        XCTAssertEqual(oversized.heightFraction, Settings.Limits.height.upperBound)
        XCTAssertEqual(oversized.fontSize, Settings.Limits.fontSize.upperBound)
        XCTAssertEqual(oversized.glassTint, Settings.Limits.glassTint.upperBound)

        let negative = try TemporaryDefaults()
        negative.defaults.set(-5, forKey: StoredKey.scrollbackLines)
        negative.defaults.set(-5.0, forKey: StoredKey.heightFraction)
        negative.defaults.set(-2.0, forKey: StoredKey.fontSize)
        negative.defaults.set(-1.0, forKey: StoredKey.glassTint)

        let undersized = Settings(defaults: negative.defaults)
        XCTAssertEqual(undersized.scrollbackLines, Settings.Limits.scrollback.lowerBound)
        XCTAssertEqual(undersized.heightFraction, Settings.Limits.height.lowerBound)
        XCTAssertEqual(undersized.fontSize, Settings.Limits.fontSize.lowerBound)
        XCTAssertEqual(undersized.glassTint, Settings.Limits.glassTint.lowerBound)
    }

    /// A value that is not a number at all is the case clamping alone does not
    /// catch: `min` and `max` return NaN unchanged, so it would survive the
    /// limits, size the panel to the whole screen and leave no slider able to
    /// drag it back. It falls back to the default instead.
    func testAStoredNumberThatIsNotANumberFallsBackToTheDefault() throws {
        let temp = try TemporaryDefaults()
        temp.defaults.set(Double.nan, forKey: StoredKey.heightFraction)
        temp.defaults.set(Double.nan, forKey: StoredKey.fontSize)
        temp.defaults.set(Double.nan, forKey: StoredKey.glassTint)
        temp.defaults.set(Double.infinity, forKey: StoredKey.heightFraction)

        let settings = Settings(defaults: temp.defaults)

        XCTAssertEqual(settings.heightFraction, 0.45)
        XCTAssertEqual(settings.fontSize, 13)
        XCTAssertEqual(settings.glassTint, 0.65)
        XCTAssertTrue(settings.heightFraction.isFinite)

        // Whatever it ends up holding, the panel it sizes is one a person can
        // still get out of.
        let frame = TerminalController.frame(
            forVisibleFrame: NSRect(x: 0, y: 0, width: 1920, height: 1055),
            heightFraction: settings.heightFraction
        )
        XCTAssertLessThan(frame.height, 1055)
    }

    /// The hotkey is re-registered off this callback, so it has to carry the
    /// combination that was just chosen and nothing else may fire.
    func testTheShortcutCallbackCarriesTheNewCombination() throws {
        let subject = try makeSettingsSubject()
        let settings = subject.settings
        let combo = KeyCombo(keyCode: UInt16(kVK_ANSI_J), carbonModifiers: UInt32(controlKey | optionKey))

        var received: KeyCombo?
        var appear = 0
        var session = 0
        var geometry = 0
        settings.onShortcutChange = { received = $0 }
        settings.onAppearanceChange = { appear += 1 }
        settings.onSessionSettingsChange = { session += 1 }
        settings.onWindowGeometryChange = { geometry += 1 }

        settings.shortcut = combo

        XCTAssertEqual(received, combo)
        XCTAssertEqual(appear, 0)
        XCTAssertEqual(session, 0)
        XCTAssertEqual(geometry, 0)
    }

    /// Colours, font and glass are repainted in place: they must not restart the
    /// shell, which would throw away whatever was running.
    func testAppearanceSettingsOnlyAskForARedraw() throws {
        let subject = try makeSettingsSubject()
        let settings = subject.settings

        var appear = 0
        var shortcut = 0
        var session = 0
        var geometry = 0
        var mode = 0
        settings.onAppearanceChange = { appear += 1 }
        settings.onShortcutChange = { _ in shortcut += 1 }
        settings.onSessionSettingsChange = { session += 1 }
        settings.onWindowGeometryChange = { geometry += 1 }
        settings.onAppearanceModeChange = { _ in mode += 1 }

        settings.darkThemeID = "solarized-dark"
        settings.lightThemeID = "solarized-light"
        settings.fontName = "Menlo"
        settings.fontSize = 14
        settings.glassTint = 0.5

        XCTAssertEqual(appear, 5)
        XCTAssertEqual(shortcut, 0)
        XCTAssertEqual(session, 0)
        XCTAssertEqual(geometry, 0)
        XCTAssertEqual(mode, 0)
    }

    /// The shell and the scrollback can only take effect in a new process, so
    /// they ask for one — and for nothing else.
    func testSessionSettingsAskForANewShell() throws {
        let subject = try makeSettingsSubject()
        let settings = subject.settings

        var session = 0
        var appear = 0
        var geometry = 0
        settings.onSessionSettingsChange = { session += 1 }
        settings.onAppearanceChange = { appear += 1 }
        settings.onWindowGeometryChange = { geometry += 1 }

        settings.shellPath = "/bin/sh"
        settings.scrollbackLines = 20000

        XCTAssertEqual(session, 2)
        XCTAssertEqual(appear, 0)
        XCTAssertEqual(geometry, 0)
    }

    /// Dragging the height slider has to resize the window while it is open, not
    /// only store a number for the next time the panel is shown.
    func testTheHeightSliderMovingIsReportedSoTheWindowFollows() throws {
        let subject = try makeSettingsSubject()
        let settings = subject.settings

        var geometry = 0
        var appear = 0
        var session = 0
        settings.onWindowGeometryChange = { geometry += 1 }
        settings.onAppearanceChange = { appear += 1 }
        settings.onSessionSettingsChange = { session += 1 }

        settings.heightFraction = 0.6

        XCTAssertEqual(geometry, 1)
        XCTAssertEqual(appear, 0)
        XCTAssertEqual(session, 0)
    }

    /// The app's own chrome follows the appearance picker, and it is told which
    /// mode to apply rather than being left to read it back. The terminal is
    /// repainted as well: the mode is what decides which of the two schemes it
    /// is painted with.
    func testTheAppearanceModeCallbackCarriesTheChosenMode() throws {
        let subject = try makeSettingsSubject()
        let settings = subject.settings

        var received: AppearanceMode?
        var appear = 0
        settings.onAppearanceModeChange = { received = $0 }
        settings.onAppearanceChange = { appear += 1 }

        settings.appearanceMode = .light

        XCTAssertEqual(received, .light)
        XCTAssertEqual(settings.appearanceMode, .light)
        XCTAssertEqual(appear, 1)
    }

    /// A light appearance paints the light scheme and a dark one the dark
    /// scheme. "Auto" is resolved against the system, so both of its slots have
    /// to be ready rather than one of them being the only one that exists.
    func testTheAppearanceDecidesWhichSchemeIsInEffect() throws {
        let subject = try makeSettingsSubject()
        let settings = subject.settings

        settings.darkThemeID = TerminalTheme.guac.id
        settings.lightThemeID = TerminalTheme.guacLight.id

        settings.appearanceMode = .dark
        XCTAssertEqual(settings.themeSlot, .dark)
        XCTAssertEqual(settings.theme.id, TerminalTheme.guac.id)

        settings.appearanceMode = .light
        XCTAssertEqual(settings.themeSlot, .light)
        XCTAssertEqual(settings.theme.id, TerminalTheme.guacLight.id)

        settings.appearanceMode = .system
        XCTAssertEqual(
            settings.themeSlot,
            settings.theme.isLight ? .light : .dark,
            "Auto has to follow the system, whichever way it is set"
        )
    }

    /// A domain from before there were two slots holds one scheme. It belongs to
    /// the slot it was picked for, and the other slot keeps its default instead
    /// of turning dark mode light.
    func testASingleStoredThemeIsMigratedToTheSlotItWasPickedFor() throws {
        let dark = try TemporaryDefaults()
        dark.defaults.set("solarized-dark", forKey: StoredKey.legacyThemeID)
        let fromDark = Settings(defaults: dark.defaults)
        XCTAssertEqual(fromDark.darkThemeID, "solarized-dark")
        XCTAssertEqual(fromDark.lightThemeID, TerminalTheme.defaultLightThemeID)

        let light = try TemporaryDefaults()
        light.defaults.set(TerminalTheme.guacLight.id, forKey: StoredKey.legacyThemeID)
        let fromLight = Settings(defaults: light.defaults)
        XCTAssertEqual(fromLight.lightThemeID, TerminalTheme.guacLight.id)
        XCTAssertEqual(fromLight.darkThemeID, TerminalTheme.defaultThemeID)
    }

    /// Picking the value that is already set is still an event: the callback is
    /// what re-registers the hotkey and moves the window, and a panel that was
    /// resized behind its back must be able to re-apply it.
    func testSettingAValueToWhatItAlreadyIsStillNotifies() throws {
        let subject = try makeSettingsSubject()
        let settings = subject.settings

        var received: AppearanceMode?
        settings.onAppearanceModeChange = { received = $0 }
        settings.appearanceMode = .system
        XCTAssertEqual(received, .system)

        var appear = 0
        settings.onAppearanceChange = { appear += 1 }
        settings.darkThemeID = TerminalTheme.defaultThemeID
        XCTAssertEqual(appear, 1)

        var geometry = 0
        settings.onWindowGeometryChange = { geometry += 1 }
        settings.heightFraction = 0.45
        XCTAssertEqual(geometry, 1)
    }

    /// Glass is a request, not a guarantee: the setting has to stay honest about
    /// what the running system will actually draw. A fully opaque tint is how
    /// the effect is switched off, so there is no second toggle to disagree
    /// with the slider.
    func testGlassNeedsBothTheSystemAndATranslucentTint() throws {
        let subject = try makeSettingsSubject()
        let settings = subject.settings

        settings.glassTint = 1
        XCTAssertFalse(settings.usesGlass)

        settings.glassTint = 0.65
        XCTAssertEqual(settings.usesGlass, Settings.glassIsSupported)
    }

    /// A domain from when the glass had its own switch: turning it off has to
    /// survive as a fully opaque tint, and turning it on has to leave the tint
    /// that was stored. Either way the old key goes, so the slider is the only
    /// thing that decides from then on.
    func testTheOldGlassSwitchBecomesATint() throws {
        let off = try TemporaryDefaults()
        off.defaults.set(false, forKey: StoredKey.legacyGlassBackground)
        off.defaults.set(0.65, forKey: StoredKey.glassTint)

        let opaque = Settings(defaults: off.defaults)
        XCTAssertEqual(opaque.glassTint, Settings.Limits.glassTint.upperBound)
        XCTAssertFalse(opaque.usesGlass)
        XCTAssertNil(off.defaults.object(forKey: StoredKey.legacyGlassBackground))
        XCTAssertEqual(
            off.defaults.object(forKey: StoredKey.glassTint) as? Double,
            Settings.Limits.glassTint.upperBound,
            "the tint the migration chose has to be the one that comes back"
        )

        let on = try TemporaryDefaults()
        on.defaults.set(true, forKey: StoredKey.legacyGlassBackground)
        on.defaults.set(0.65, forKey: StoredKey.glassTint)

        let translucent = Settings(defaults: on.defaults)
        XCTAssertEqual(translucent.glassTint, 0.65, accuracy: 0.000_001)
        XCTAssertNil(on.defaults.object(forKey: StoredKey.legacyGlassBackground))
    }

    /// The terminal is only ever handed a complete palette, so a selected theme
    /// that resolved to fewer than sixteen colours would be a half-coloured
    /// session.
    func testTheSelectedThemeArrivesWithAllSixteenColours() throws {
        let subject = try makeSettingsSubject()
        let settings = subject.settings

        XCTAssertEqual(settings.theme.id, TerminalTheme.defaultThemeID)
        XCTAssertEqual(settings.theme.ansi.count, 16)
    }

    /// A font name from a machine that no longer exists must still give a
    /// terminal, and a fixed-pitch one, or columns stop lining up.
    func testAnUnknownFontFallsBackToAFixedPitchSystemFont() throws {
        let subject = try makeSettingsSubject()
        let settings = subject.settings

        settings.fontName = "GuacTerm No Such Family"

        let font = settings.font
        XCTAssertEqual(font.pointSize, CGFloat(settings.fontSize))
        XCTAssertTrue(font.isFixedPitch)
    }

    /// Zellij, then tmux, then the account's login shell, and never anything that
    /// cannot be launched: tabs and splits are what a multiplexer is for, so a
    /// machine that has one starts on it.
    func testTheFirstLaunchShellPrefersZellijThenTmuxThenTheLoginShell() {
        let zellij = Settings.resolveExecutable("zellij")
        let tmux = Settings.resolveExecutable("tmux")

        if let zellij {
            XCTAssertEqual(Settings.firstLaunchShell, zellij, "zellij is the first choice")
        } else if let tmux {
            XCTAssertEqual(Settings.firstLaunchShell, tmux, "tmux is the second choice")
        } else {
            XCTAssertEqual(Settings.firstLaunchShell, Settings.accountLoginShell)
        }
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: Settings.firstLaunchShell))
    }

    /// The multiplexer is picked on the very first launch and never again: the
    /// answer goes into the domain, so every later launch reads a setting rather
    /// than looking at what is installed. Installing zellij next month must not
    /// replace a shell someone has been using for months.
    func testTheShellChosenAtFirstLaunchIsStoredAndNotChosenAgain() throws {
        let temp = try TemporaryDefaults()
        let settings = Settings(defaults: temp.defaults)

        XCTAssertEqual(settings.shellPath, Settings.firstLaunchShell)
        XCTAssertEqual(temp.defaults.string(forKey: StoredKey.shellPath), Settings.firstLaunchShell)

        settings.shellPath = "/bin/sh"
        XCTAssertEqual(Settings(defaults: temp.defaults).shellPath, "/bin/sh")
    }

    /// An emptied field means "just the account's login shell", which is a choice
    /// as much as any other: a relaunch must not fill the multiplexer back in.
    func testAnEmptiedShellFieldStaysEmpty() throws {
        let temp = try TemporaryDefaults()
        Settings(defaults: temp.defaults).shellPath = ""

        let relaunched = Settings(defaults: temp.defaults)
        XCTAssertEqual(relaunched.shellPath, "")
        XCTAssertEqual(relaunched.shellLaunch, .program(Settings.accountLoginShell))
    }

    /// The field is stored exactly as typed so a person can see what they wrote,
    /// but the surrounding spaces typing leaves behind must not become part of
    /// the command.
    func testTheShellLineDropsTheSpacesAroundIt() throws {
        let subject = try makeSettingsSubject()
        let settings = subject.settings

        settings.shellPath = "  /bin/zsh \n"

        XCTAssertEqual(settings.shellLine, "/bin/zsh")
        XCTAssertEqual(settings.shellPath, "  /bin/zsh \n")
    }

    /// The Shell menu is a list of promises: every entry it offers is launched
    /// when clicked, in a list a person can scan without seeing the same shell
    /// twice. A shell from another platform in there is a click that fails.
    func testTheShellMenuOnlyOffersProgramsThatAreReallyInstalled() {
        let shells = Settings.availableShells

        XCTAssertFalse(shells.isEmpty)
        XCTAssertEqual(Set(shells).count, shells.count, "no shell is offered twice")
        XCTAssertTrue(shells.contains(Settings.accountLoginShell))
        XCTAssertTrue(shells.allSatisfy { $0.hasPrefix("/") })

        for shell in shells {
            var isDirectory: ObjCBool = false
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: shell, isDirectory: &isDirectory),
                "\(shell) is offered but not on disk"
            )
            XCTAssertFalse(isDirectory.boolValue, "\(shell) is a directory")
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: shell), "\(shell) is not executable")
        }

        XCTAssertTrue(
            shells.allSatisfy { ($0 as NSString).lastPathComponent != "termux" },
            "termux cannot run on macOS"
        )
    }

    /// A multiplexer is not a shell. The menu offers `tmux` and `zellij` beside
    /// the shells, and the difference is what `$SHELL` has to say: a multiplexer
    /// reads it to decide what to start in a new pane.
    func testMultiplexersAreNotShells() {
        for program in ["zellij", "/opt/homebrew/bin/zellij", "tmux", "/opt/homebrew/bin/tmux", "screen"] {
            XCTAssertFalse(Settings.isShell(program), "\(program) is not a shell")
        }
    }

    /// Every shell macOS lists, and the ones people install on top of it, are
    /// recognised whether they are written as a name or as a path.
    func testShellsAreRecognisedByNameAndByPath() {
        for program in [
            "/bin/zsh",
            "/bin/bash",
            "/bin/sh",
            "/bin/dash",
            "/bin/csh",
            "/bin/tcsh",
            "/bin/ksh",
            "/opt/homebrew/bin/fish",
            "/opt/homebrew/bin/nu",
            "/opt/homebrew/bin/xonsh",
            "/opt/homebrew/bin/pwsh",
            "zsh",
            "fish",
        ] {
            XCTAssertTrue(Settings.isShell(program), "\(program) is a shell")
        }
    }

    /// The account's login shell is always recognised, whatever it is called:
    /// an exotic one that matches no naming pattern has to be found in
    /// `/etc/shells` rather than be mistaken for a multiplexer.
    func testTheAccountLoginShellIsAlwaysAShell() {
        XCTAssertTrue(Settings.isShell(Settings.accountLoginShell))
    }
}
