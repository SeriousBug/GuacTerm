import Foundation

/// Where the shells on this Mac are and how to tell one from a program that
/// runs inside one.
///
/// An app launched from Finder inherits a very short `PATH`, so nothing here
/// can be left to the environment: the account's own login shell comes from the
/// user database and a typed name is looked up in the places shells and
/// multiplexers are actually installed.
@MainActor
extension Settings {
    nonisolated static var accountLoginShell: String {
        if let entry = getpwuid(getuid()), let raw = entry.pointee.pw_shell {
            let shell = String(cString: raw)
            if !shell.isEmpty, FileManager.default.isExecutableFile(atPath: shell) {
                return shell
            }
        }
        if let shell = ProcessInfo.processInfo.environment["SHELL"],
           FileManager.default.isExecutableFile(atPath: shell)
        {
            return shell
        }
        return "/bin/zsh"
    }

    /// Turns whatever the user typed into an absolute path to a program, or
    /// `nil` if it is not one.
    ///
    /// Typing is the way to pick a shell here: `zsh` or `zellij` is faster than
    /// hunting for `/opt/homebrew/bin/zellij` in a file panel, and multiplexers
    /// are exactly the kind of thing GuacTerm expects people to run. A bare name
    /// is looked up in `PATH` and in the usual install locations, because an app
    /// launched from Finder inherits a very short `PATH`.
    static func resolveExecutable(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let expanded = (trimmed as NSString).expandingTildeInPath
        if expanded.contains("/") {
            return isExecutableFile(expanded) ? expanded : nil
        }

        for directory in executableSearchDirectories {
            let candidate = (directory as NSString).appendingPathComponent(expanded)
            if isExecutableFile(candidate) {
                return candidate
            }
        }
        return nil
    }

    /// True when a program is a shell rather than something that runs inside one.
    ///
    /// The Shell field takes multiplexers as readily as shells — the menu offers
    /// `tmux` and `zellij` — and the difference matters for `$SHELL`: a
    /// multiplexer reads it to decide what to start in each new pane, while a
    /// shell's own startup files read it to decide whether they are in a shell.
    nonisolated static func isShell(_ program: String) -> Bool {
        let name = (program as NSString).lastPathComponent.lowercased()
        // Every shell GuacTerm is likely to meet ends in `sh` — zsh, bash, dash,
        // fish, xonsh, pwsh — and `nu` is the one that does not.
        if name == "nu" || name.hasSuffix("sh") {
            return true
        }
        // Anything else macOS lists as a login shell, whatever it is called.
        return systemShells.contains(program)
    }

    /// The login shells macOS knows about, from `/etc/shells`, which is the list
    /// `chsh` and Ftpd go by.
    private nonisolated static var systemShells: [String] {
        guard let contents = try? String(contentsOfFile: "/etc/shells", encoding: .utf8) else {
            return []
        }
        return contents
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// `isExecutableFile` alone is true for directories, which is not something
    /// that can be launched.
    private static func isExecutableFile(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else { return false }
        return FileManager.default.isExecutableFile(atPath: path)
    }

    /// Where a bare command name is searched for: the app's own `PATH` first,
    /// then Homebrew, MacPorts and the system directories.
    private static var executableSearchDirectories: [String] {
        var directories: [String] = []
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            directories += path.split(separator: ":").map(String.init)
        }
        directories += [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ]

        var seen = Set<String>()
        return directories.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Programs offered in the Shell menu: every login shell macOS knows about,
    /// plus the shells and multiplexers GuacTerm expects people to run inside it
    /// (the modern shells are rarely listed in `/etc/shells`).
    ///
    /// Anything that is not actually installed is dropped, so the menu never
    /// offers a path that would fail to launch.
    static var availableShells: [String] {
        var candidates: [String] = [accountLoginShell]
        candidates += systemShells

        // Resolved against `PATH`, so this covers Homebrew on Apple silicon
        // (`/opt/homebrew/bin`) as well as Intel and manual installs. A name that
        // is not installed never appears.
        candidates += ["fish", "nu", "tmux", "zellij"].compactMap(resolveExecutable)

        var seen = Set<String>()
        return candidates.compactMap(resolveExecutable).filter { seen.insert($0).inserted }
    }
}
