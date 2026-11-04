@testable import GuacTerm
import XCTest

/// What the shell inside the panel is handed when it starts.
///
/// GuacTerm is launched from Finder, where it inherits almost nothing from the
/// user's interactive session, so this list is the difference between a terminal
/// where `ls` colours its output and one where everything is monochrome, and
/// between a `vim` that reads UTF-8 and one that draws mojibake.
final class ShellEnvironmentTests: XCTestCase {
    /// The built environment as a dictionary. `make` returns `KEY=value` strings
    /// in whatever order the process environment enumerated in, and that order
    /// changes from run to run, so nothing here compares the array itself.
    private func environment(shell: String = "/bin/zsh") -> [String: String] {
        environmentDictionary(ShellEnvironment.make(shell: shell))
    }

    /// Programs decide colours and capabilities from these four variables, and
    /// the names are not interchangeable: `TERM_PROGRAM` is what makes tmux and
    /// Claude Code offer images and clipboard integration at all.
    func testTerminalAnnouncesItselfAsATruecolorXterm() {
        let environment = environment()
        XCTAssertEqual(environment["TERM"], "xterm-256color")
        XCTAssertEqual(environment["COLORTERM"], "truecolor")
        XCTAssertEqual(environment["TERM_PROGRAM"], AppInfo.name)
        XCTAssertEqual(environment["TERM_PROGRAM_VERSION"], AppInfo.version)
    }

    /// `$SHELL` is what the shell's own startup files and every script they call
    /// read to decide which shell they are running in, so it has to be the
    /// program that was actually started, not whatever this process inherited.
    func testTheShellSettingIsWhatTheShellSeesAsItself() {
        XCTAssertEqual(environment(shell: "/bin/zsh")["SHELL"], "/bin/zsh")
        XCTAssertEqual(environment(shell: "zsh")["SHELL"], "zsh")
        XCTAssertEqual(environment(shell: "/bin/sh")["SHELL"], "/bin/sh")
    }

    /// Two windows in a terminal that does tabs (and in anything recording which
    /// session a command came from) are told apart by this identifier, so it has
    /// to be a real UUID and a new one for each session.
    func testEachSessionGetsItsOwnIdentifier() throws {
        let first = try XCTUnwrap(environment()["TERM_SESSION_ID"])
        XCTAssertNotNil(UUID(uuidString: first), "\(first) is not a session identifier")

        let second = try XCTUnwrap(environment()["TERM_SESSION_ID"])
        XCTAssertNotEqual(first, second)
    }

    /// Launch Services stamps these on an app it starts, and they confuse tools
    /// that inspect them — a build system that thinks it is running inside XPC
    /// takes a different path entirely. The terminal hands over a clean sheet
    /// instead.
    func testLaunchServicesLeftoversAreRemoved() {
        let environment = environment()
        XCTAssertNil(environment["XPC_FLAGS"])
        XCTAssertNil(environment["XPC_SERVICE_NAME"])
    }

    /// A shell with no `HOME` writes its history into the filesystem root, and a
    /// process with no `PATH` cannot find its own commands. Every one of these
    /// has to be filled in when the launching environment had none — and left
    /// alone when it had one, because this app must not overwrite the account it
    /// was started by.
    func testTheEssentialsAreAlwaysFilledIn() throws {
        let inherited = ProcessInfo.processInfo.environment
        let environment = environment()

        for key in ["HOME", "USER", "LOGNAME", "PATH", "LANG"] {
            let value = try XCTUnwrap(environment[key], "\(key) is missing")
            XCTAssertFalse(value.isEmpty, "\(key) is empty")
            if let existing = inherited[key], !existing.isEmpty {
                XCTAssertEqual(value, existing, "\(key) was already set and has to be kept")
            }
        }

        if inherited["HOME"]?.isEmpty ?? true {
            XCTAssertEqual(environment["HOME"], NSHomeDirectory())
        }
        if inherited["LANG"]?.isEmpty ?? true {
            XCTAssertTrue(
                try XCTUnwrap(environment["LANG"]).hasSuffix("UTF-8"),
                "tools like vim need a UTF-8 locale or they render mojibake"
            )
        }
    }

    /// `PATH` is the one variable the app must not invent: it is what the process
    /// already had, because a `PATH` that drops the user's own directories makes
    /// every command in them disappear. The fallback only exists for a launch
    /// that inherited nothing.
    func testTheSearchPathTheProcessAlreadyHadIsKept() throws {
        let path = try XCTUnwrap(environment()["PATH"])
        let inherited = ProcessInfo.processInfo.environment["PATH"]

        if let inherited, !inherited.isEmpty {
            XCTAssertEqual(path, inherited)
        } else {
            XCTAssertTrue(path.contains("/usr/bin"), "the fallback has to find the system's own tools")
        }
    }

    /// The environment is a list of `KEY=value` lines, so a key appearing twice
    /// would leave it to whoever reads it first which one a program sees. Their
    /// order is deliberately not asserted: it comes out of a dictionary.
    func testEveryVariableAppearsExactlyOnce() {
        let entries = ShellEnvironment.make(shell: "/bin/zsh")
        let keys = entries.map { entry in
            entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        }

        XCTAssertEqual(keys.count, Set(keys).count, "duplicate \(keys)")
        XCTAssertEqual(entries.count, environmentDictionary(entries).count)
        XCTAssertFalse(entries.isEmpty)
    }
}
