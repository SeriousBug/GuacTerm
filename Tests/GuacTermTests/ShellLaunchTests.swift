@testable import GuacTerm
import XCTest

/// The Shell field is the most-typed field in the app, and it takes two very
/// different things: a program, which is exec'd as it is, and a command line,
/// which only a shell can make sense of. Getting that judgement wrong is silent
/// — the panel opens with a plain login shell, or with the user's multiplexer
/// missing — so every classification is pinned here.
@MainActor
final class ShellLaunchTests: XCTestCase {
    /// Domains that must outlive the test: `Settings` writes to them as the
    /// shell field is set, and a deallocated `TemporaryDefaults` wipes them.
    private var shellLaunchDomains: [TemporaryDefaults] = []

    /// Settings whose shell field holds `line`.
    private func makeShellLaunchSettings(_ line: String) throws -> Settings {
        let temp = try TemporaryDefaults()
        shellLaunchDomains.append(temp)
        let settings = Settings(defaults: temp.defaults)
        settings.shellPath = line
        return settings
    }

    /// What `line` would start, as the terminal controller would launch it.
    private func shellLaunchOf(_ line: String) throws -> ShellLaunch {
        try makeShellLaunchSettings(line).shellLaunch
    }

    /// A command line that only a shell understands, run as such. Handing this
    /// to `exec` would fail and leave an empty panel, and stripping the `||`
    /// would quietly start a plain `zellij` instead of attaching to the session
    /// that is already there.
    func testAnOrListRunsThroughTheLoginShellVerbatim() throws {
        let line = "zellij attach || zellij"
        XCTAssertEqual(
            try shellLaunchOf(line),
            .command(shell: Settings.accountLoginShell, line: line)
        )
    }

    /// Nothing typed at all is not an error: the account's own shell starts.
    func testAnEmptyOrBlankShellFieldFallsBackToTheAccountLoginShell() throws {
        for line in ["", " ", "   ", "\n", "\t \n "] {
            XCTAssertEqual(
                try shellLaunchOf(line),
                .program(Settings.accountLoginShell),
                "for \(line.debugDescription)"
            )
        }
    }

    /// A whole path to a program is that program: it is named as a login shell
    /// and exec'd, so no shell gets in between.
    func testAnAbsoluteProgramIsLaunchedAsItIs() throws {
        let directory = try TemporaryDirectory()
        let program = try makeExecutableFile(named: "guacsh", in: directory.url)

        XCTAssertEqual(try shellLaunchOf(program.path), .program(program.path))
    }

    /// A path with a space in it is still one program. It has to be exec'd
    /// rather than handed to a shell, where the space would split it in two.
    func testAProgramWhosePathHasSpacesIsNeverShellParsed() throws {
        let directory = try TemporaryDirectory()
        let program = try makeExecutableFile(named: "my shell", in: directory.url)
        XCTAssertTrue(program.path.contains(" "))

        XCTAssertEqual(try shellLaunchOf(program.path), .program(program.path))
    }

    /// Typing `fish` or `zellij` has to work — an app launched from the Finder
    /// inherits a short `PATH`, so the name is looked up where the program
    /// really is and the absolute path is what gets launched.
    func testABareNameIsResolvedToWhereTheProgramActuallyLives() throws {
        for name in ["ls", "zsh"] {
            let resolved = try XCTUnwrap(Settings.resolveExecutable(name), name)
            XCTAssertTrue(resolved.hasPrefix("/"), name)
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: resolved), name)
            XCTAssertEqual(try shellLaunchOf(name), .program(resolved), name)
        }
    }

    /// A directory is not a program. Passing one to `exec` fails, so the line
    /// goes to a shell instead — which is also what makes a folder that happens
    /// to be named like a command harmless.
    func testADirectoryIsNotTreatedAsAProgram() throws {
        let directory = try TemporaryDirectory()

        XCTAssertEqual(
            try shellLaunchOf(directory.url.path),
            .command(shell: Settings.accountLoginShell, line: directory.url.path)
        )
    }

    /// Arguments make it a command line, kept exactly as typed: the user's own
    /// spacing and quoting are theirs to get right for their shell.
    func testArgumentsTurnTheLineIntoACommandKeptExactly() throws {
        for line in [
            "ls -l",
            "  ls -l  ",
            "echo $HOME",
            "exec fish -l",
        ] {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(
                try shellLaunchOf(line),
                .command(shell: Settings.accountLoginShell, line: trimmed),
                "for \(line.debugDescription)"
            )
        }
    }

    /// A newline is a command separator, so a two-line field is a command line
    /// and the newline has to survive: joining the lines would run one command
    /// that does not exist.
    func testANewlineInTheFieldIsKeptAsPartOfTheCommand() throws {
        let line = "echo one\necho two"
        XCTAssertEqual(
            try shellLaunchOf(line),
            .command(shell: Settings.accountLoginShell, line: line)
        )
    }

    /// A program name that is not ASCII cannot be exec'd by path from here, so
    /// it stays a command line and the shell reports the mistake itself.
    func testANonASCIIProgramNameStaysACommandLine() throws {
        for line in ["zëllij", "日本語"] {
            XCTAssertEqual(
                try shellLaunchOf(line),
                .command(shell: Settings.accountLoginShell, line: line),
                "for \(line)"
            )
        }
    }

    // MARK: - Multiplexer sessions

    /// A multiplexer is not launched as it is: it is told to attach to the
    /// session GuacTerm keeps, and to start that session when it is not running.
    /// Launched plainly, each pull-down would start a new empty session and leave
    /// the work from the last one running where nothing reaches it.
    ///
    /// The names are made up here on purpose: what decides this is the name of
    /// the program, not where this machine happens to have installed it.
    func testAMultiplexerIsStartedAttachedToTheNamedSession() throws {
        let directory = try TemporaryDirectory()
        let zellij = try makeExecutableFile(named: "zellij", in: directory.url)
        let tmux = try makeExecutableFile(named: "tmux", in: directory.url)

        XCTAssertEqual(
            try shellLaunchOf(zellij.path),
            .session(program: zellij.path, arguments: ["attach", "--create", Settings.sessionName])
        )
        XCTAssertEqual(
            try shellLaunchOf(tmux.path),
            .session(program: tmux.path, arguments: ["new-session", "-A", "-s", Settings.sessionName])
        )
    }

    /// Arguments in the field are the user's own line, not GuacTerm's: someone
    /// who typed which session to attach to gets that session, verbatim, through
    /// a shell that understands it.
    func testAMultiplexerWithArgumentsOfItsOwnStaysACommandLine() throws {
        for line in [
            "tmux attach -t main",
            "tmux new -s work",
            "zellij attach main",
            "zellij --session work",
        ] {
            XCTAssertEqual(
                try shellLaunchOf(line),
                .command(shell: Settings.accountLoginShell, line: line),
                "for \(line.debugDescription)"
            )
        }
    }

    /// Attaching does not make a multiplexer a shell: `$SHELL` stays the account's
    /// login shell, so a new pane or split starts the shell people expect rather
    /// than another zellij inside this one.
    func testAnAttachedSessionStillNamesTheLoginShell() {
        let launch = ShellLaunch.session(
            program: "/opt/homebrew/bin/zellij",
            arguments: ["attach", "--create", Settings.sessionName]
        )

        XCTAssertEqual(launch.announcedShell, Settings.accountLoginShell)
    }

    // MARK: - Resolving a program

    /// An empty field is not a program, so nothing is resolved from it.
    func testResolveExecutableIgnoresAnEmptyField() {
        XCTAssertNil(Settings.resolveExecutable(""))
        XCTAssertNil(Settings.resolveExecutable("   "))
        XCTAssertNil(Settings.resolveExecutable("\n"))
    }

    /// A path to a real program is returned unchanged, with the spaces typing
    /// left around it removed so the launch cannot fail on them.
    func testResolveExecutableReturnsAProgramAndTrimsTheSpacesAroundIt() throws {
        let directory = try TemporaryDirectory()
        let program = try makeExecutableFile(named: "guacsh", in: directory.url)

        XCTAssertEqual(Settings.resolveExecutable(program.path), program.path)
        XCTAssertEqual(Settings.resolveExecutable("  \(program.path)\n"), program.path)
    }

    /// Whatever cannot be launched resolves to nothing — a directory (which
    /// `isExecutableFile` alone would accept), the home directory, a path that
    /// is not there, and a bare name that is not installed.
    func testResolveExecutableRefusesThingsThatCannotBeLaunched() throws {
        let directory = try TemporaryDirectory()

        XCTAssertNil(Settings.resolveExecutable(directory.url.path), "a directory is not a program")
        XCTAssertNil(Settings.resolveExecutable("~"), "the home directory is a directory")
        XCTAssertNil(Settings.resolveExecutable(directory.url.appendingPathComponent("missing").path))
        XCTAssertNil(Settings.resolveExecutable("guacterm-no-such-program"))

        // A file that is there but not executable is still not a program, which
        // is what a hand-made script without its execute bit looks like.
        let notExecutable = try directory.write(Data("#!/bin/sh\n".utf8), as: "not executable")
        XCTAssertNil(Settings.resolveExecutable(notExecutable.path))
    }

    // MARK: - What `$SHELL` says inside the session

    /// A shell that was launched is the shell the session is running, so
    /// `$SHELL` names it — that is what its own startup files read.
    func testALaunchedShellAnnouncesItself() {
        for program in ["/bin/zsh", "/opt/homebrew/bin/fish", "/opt/homebrew/bin/nu"] {
            XCTAssertEqual(ShellLaunch.program(program).announcedShell, program)
        }
    }

    /// A multiplexer is not the user's shell, and saying it is makes it start
    /// itself in every new pane, since that is what it reads `$SHELL` for. The
    /// session keeps the account's login shell instead, and the login shell in
    /// the user database is never touched by any of this.
    func testAMultiplexerLeavesTheShellVariableToTheLoginShell() {
        for program in ["/opt/homebrew/bin/zellij", "/opt/homebrew/bin/tmux"] {
            XCTAssertEqual(ShellLaunch.program(program).announcedShell, Settings.accountLoginShell)
        }
    }

    /// A command line is already run by the account's login shell, which is what
    /// `$SHELL` then names — not the program the line happens to start.
    func testACommandLineAnnouncesTheShellThatRunsIt() {
        let launch = ShellLaunch.command(shell: "/bin/zsh", line: "zellij attach || zellij")

        XCTAssertEqual(launch.announcedShell, "/bin/zsh")
    }

    // MARK: - Warning about a mistyped program

    /// A single mistyped word is worth a note next to the field: the panel would
    /// otherwise open and close again before anything could be read.
    func testASingleWordThatIsNotAnInstalledProgramIsFlagged() throws {
        XCTAssertTrue(try makeShellLaunchSettings("zshi").shellIsUninstalledProgram)
        XCTAssertTrue(try makeShellLaunchSettings("/opt/homebrew/bin/nope").shellIsUninstalledProgram)
    }

    /// Program names and command lines must never be flagged: a red warning on a
    /// working setting teaches people to ignore the warning.
    func testInstalledProgramsAndCommandLinesAreNotFlagged() throws {
        for line in [
            "zsh",
            "ls -l",
            "echo $HOME",
            "zellij attach || zellij",
            "",
        ] {
            XCTAssertFalse(
                try makeShellLaunchSettings(line).shellIsUninstalledProgram,
                "\(line.debugDescription) should not be flagged"
            )
        }
    }
}
