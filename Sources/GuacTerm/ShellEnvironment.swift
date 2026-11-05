import Foundation

/// Builds the environment handed to a new shell.
///
/// A bundle launched from Finder inherits almost nothing from the user's
/// interactive session, so the variables terminals are expected to provide have
/// to be supplied here. The login shell (`-zsh`) then sources the user's own
/// startup files on top.
enum ShellEnvironment {
    static func make(shell: String) -> [String] {
        var environment = ProcessInfo.processInfo.environment

        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = AppInfo.name
        environment["TERM_PROGRAM_VERSION"] = AppInfo.version
        environment["TERM_SESSION_ID"] = UUID().uuidString
        // The shell running in the session, not necessarily the program that was
        // launched: see `ShellLaunch.announcedShell`. This is the child's
        // environment only — GuacTerm never changes the account's login shell.
        environment["SHELL"] = shell

        let userName = NSUserName()
        let home = NSHomeDirectory()

        if environment["HOME"]?.isEmpty ?? true {
            environment["HOME"] = home
        }
        if environment["USER"]?.isEmpty ?? true {
            environment["USER"] = userName
        }
        if environment["LOGNAME"]?.isEmpty ?? true {
            environment["LOGNAME"] = userName
        }
        if environment["PATH"]?.isEmpty ?? true {
            environment["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        }
        // Terminals must speak UTF-8 or tools like vim render mojibake.
        if environment["LANG"]?.isEmpty ?? true {
            environment["LANG"] = "en_US.UTF-8"
        }

        // Launch Services-specific leftovers confuse some build tools.
        environment.removeValue(forKey: "XPC_FLAGS")
        environment.removeValue(forKey: "XPC_SERVICE_NAME")

        return environment.map { "\($0.key)=\($0.value)" }
    }
}
