import AppKit
import ServiceManagement

/// How GuacTerm's own windows and menus look.
///
/// This is chrome only: the terminal itself is coloured by the selected theme,
/// so a light theme in a dark app (or the reverse) stays possible.
enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` means "follow the system".
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// What a new session runs, worked out from the Shell setting.
///
/// The setting takes either a program or a whole command line, because the two
/// are useful in different situations and telling them apart is easy: a single
/// program can be launched directly, while `zellij attach || zellij` only means
/// something to a shell.
enum ShellLaunch: Equatable, Sendable {
    /// A program to exec, e.g. `/bin/zsh` or `/opt/homebrew/bin/zellij`. It is
    /// named as a login shell, so it reads the startup files Terminal.app would.
    case program(String)

    /// A command line handed to the account's login shell with `-c`, e.g.
    /// `zellij attach || zellij`.
    case command(shell: String, line: String)
}

/// Everything the user can change, persisted in `UserDefaults`.
///
/// This is deliberately the *entire* configuration surface of the app. GuacTerm
/// has no tabs, no splits, no profiles and no plugins: if you want those, run
/// tmux or zellij inside the terminal.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    /// Ranges enforced by the UI and re-checked here, so a hand-edited
    /// `defaults write` cannot produce a window taller than the screen.
    enum Limits {
        static let scrollback = 0 ... 1_000_000
        static let height = 0.15 ... 1.0
        static let fontSize = 8.0 ... 48.0
        /// Below 20% the theme is barely there and text stops being readable.
        static let glassTint = 0.2 ... 1.0
    }

    /// Liquid Glass arrived in macOS 26. On anything older the panel simply
    /// keeps its solid theme background, and Settings hides the controls.
    static var glassIsSupported: Bool {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }

    // MARK: - Stored settings

    /// The global shortcut that shows and hides the terminal.
    @Published var shortcut: KeyCombo {
        didSet {
            persist()
            onShortcutChange?(shortcut)
        }
    }

    /// Absolute path of the shell or command to launch, e.g. `/bin/zsh`,
    /// `zellij`, or `zellij attach || zellij`. See ``shellLaunch``.
    @Published var shellPath: String {
        didSet {
            persist()
            onSessionSettingsChange?()
        }
    }

    /// How many lines of history to keep. Applies to the next session.
    @Published var scrollbackLines: Int {
        didSet {
            persist()
            onSessionSettingsChange?()
        }
    }

    /// Identifier of the selected `TerminalTheme`.
    @Published var themeID: String {
        didSet {
            persist()
            onAppearanceChange?()
        }
    }

    /// Height of the drop-down window, as a fraction of the screen's height.
    @Published var heightFraction: Double {
        didSet {
            persist()
            onWindowGeometryChange?()
        }
    }

    /// Font family used for the terminal, e.g. `Menlo`.
    @Published var fontName: String {
        didSet {
            persist()
            onAppearanceChange?()
        }
    }

    /// Font size in points.
    @Published var fontSize: Double {
        didSet {
            persist()
            onAppearanceChange?()
        }
    }

    /// Look of GuacTerm's windows and menus.
    @Published var appearanceMode: AppearanceMode {
        didSet {
            persist()
            onAppearanceModeChange?(appearanceMode)
        }
    }

    /// Drop the terminal away when another app takes focus.
    @Published var hideOnFocusLoss: Bool {
        didSet { persist() }
    }

    /// Draw the terminal on macOS's Liquid Glass material instead of a solid
    /// theme background. Ignored on systems without `NSGlassEffectView`.
    @Published var glassBackground: Bool {
        didSet {
            persist()
            onAppearanceChange?()
        }
    }

    /// How much of the theme background is painted over that glass: 1 is
    /// effectively solid, 0.2 lets the desktop through almost untouched.
    @Published var glassTint: Double {
        didSet {
            persist()
            onAppearanceChange?()
        }
    }

    /// True only when the user asked for glass *and* the system can draw it.
    var usesGlass: Bool {
        glassBackground && Self.glassIsSupported
    }

    /// Start GuacTerm when the user logs in. Change it through
    /// ``setLaunchAtLogin(_:)`` so the system's registration stays in sync.
    @Published private(set) var launchAtLogin: Bool

    // MARK: - Transient state

    /// Set when the system refuses the requested shortcut, so the settings
    /// window can explain why the hotkey does nothing.
    @Published var shortcutIssue: String?

    // MARK: - Change notifications

    /// Called when the global shortcut changes, so it can be re-registered.
    var onShortcutChange: ((KeyCombo) -> Void)?

    /// Called when something that only affects drawing changes.
    var onAppearanceChange: (() -> Void)?

    /// Called when a setting changes that needs a brand new shell process.
    var onSessionSettingsChange: (() -> Void)?

    /// Called when the panel's size changes, so an open panel can follow along.
    var onWindowGeometryChange: (() -> Void)?

    /// Called when the window appearance changes.
    var onAppearanceModeChange: ((AppearanceMode) -> Void)?

    // MARK: - Derived

    /// The selected theme, resolved against the bundled catalog *and* the
    /// schemes the user imported, falling back to the default theme when the
    /// identifier points at a theme whose file has since been removed.
    var theme: TerminalTheme {
        ThemeLibrary.shared.theme(id: themeID)
    }

    /// The `NSFont` handed to SwiftTerm.
    var font: NSFont {
        let manager = NSFontManager.shared
        if let family = manager.availableFontFamilies.first(where: {
            $0.compare(fontName, options: .caseInsensitive) == .orderedSame
        }), let font = manager.font(withFamily: family, traits: [], weight: 5, size: fontSize) {
            return font
        }
        if let font = NSFont(name: fontName, size: fontSize) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    /// The Shell field without the spaces typing leaves around it.
    var shellLine: String {
        shellPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What a new session runs, from whatever is typed in Settings.
    ///
    /// Typing is the way to pick a shell here: `zsh` or `zellij` is faster than
    /// hunting for `/opt/homebrew/bin/zellij` in a file panel. When what is
    /// typed *is* a program — a bare name found in `PATH`, or a path — it is
    /// launched directly and named as a login shell.
    ///
    /// Anything else is a command line, and there is no way to exec that: `||`,
    /// spaces between arguments and quoting all have to be interpreted. Those
    /// run through the account's login shell with `-c`, so `zellij attach ||
    /// zellij` works and still reads the same startup files it would in
    /// Terminal.app.
    var shellLaunch: ShellLaunch {
        let line = shellLine
        guard !line.isEmpty else { return .program(Self.accountLoginShell) }
        if let program = Self.resolveExecutable(line) {
            return .program(program)
        }
        return .command(shell: Self.accountLoginShell, line: line)
    }

    /// True when the Shell field holds one bare word that is not an installed
    /// program.
    ///
    /// That is usually a typo — `zshi` instead of `zsh` — and the panel would
    /// open and close again before anything could be read, so the pane says so.
    /// It is only a note: a shell function or alias the user's own startup
    /// files define works fine through `-c`.
    var shellIsUninstalledProgram: Bool {
        guard case let .command(_, line) = shellLaunch,
              line.split(whereSeparator: \.isWhitespace).count == 1 else { return false }
        return !line.contains { #"|&;<>()$`\"'"#.contains($0) }
    }

    // MARK: - Loading and saving

    private enum Key: String {
        case shortcut
        case shellPath
        case scrollbackLines
        case themeID
        case heightFraction
        case fontName
        case fontSize
        case hideOnFocusLoss
        case glassBackground
        case glassTint
        case launchAtLogin
        case appearanceMode
    }

    private let defaults: UserDefaults
    private var isLoading = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isLoading = true

        shortcut = Self.loadShortcut(defaults) ?? .default
        shellPath = defaults.string(forKey: Key.shellPath.rawValue) ?? Self.accountLoginShell
        scrollbackLines = defaults.object(forKey: Key.scrollbackLines.rawValue) as? Int ?? 10000
        themeID = defaults.string(forKey: Key.themeID.rawValue) ?? TerminalTheme.defaultThemeID
        heightFraction = defaults.object(forKey: Key.heightFraction.rawValue) as? Double ?? 0.45
        fontName = defaults.string(forKey: Key.fontName.rawValue) ?? Self.defaultFontName
        fontSize = defaults.object(forKey: Key.fontSize.rawValue) as? Double ?? 13
        hideOnFocusLoss = defaults.object(forKey: Key.hideOnFocusLoss.rawValue) as? Bool ?? true
        glassBackground = defaults.object(forKey: Key.glassBackground.rawValue) as? Bool ?? false
        glassTint = defaults.object(forKey: Key.glassTint.rawValue) as? Double ?? 0.65
        appearanceMode = defaults
            .string(forKey: Key.appearanceMode.rawValue)
            .flatMap(AppearanceMode.init(rawValue:)) ?? .system
        launchAtLogin = Self.isLaunchAtLoginEnabled

        isLoading = false

        // A theme can change without `themeID` changing (an imported file
        // replaced by an updated copy) and can disappear entirely (its file
        // moved to the Trash), so repaints follow the library rather than the
        // identifier alone.
        ThemeLibrary.shared.onChange = { [weak self] in
            self?.onAppearanceChange?()
        }
    }

    private func persist() {
        guard !isLoading else { return }
        defaults.set(try? JSONEncoder().encode(shortcut), forKey: Key.shortcut.rawValue)
        defaults.set(shellPath, forKey: Key.shellPath.rawValue)
        defaults.set(scrollbackLines, forKey: Key.scrollbackLines.rawValue)
        defaults.set(themeID, forKey: Key.themeID.rawValue)
        defaults.set(heightFraction, forKey: Key.heightFraction.rawValue)
        defaults.set(fontName, forKey: Key.fontName.rawValue)
        defaults.set(fontSize, forKey: Key.fontSize.rawValue)
        defaults.set(hideOnFocusLoss, forKey: Key.hideOnFocusLoss.rawValue)
        defaults.set(glassBackground, forKey: Key.glassBackground.rawValue)
        defaults.set(glassTint, forKey: Key.glassTint.rawValue)
        defaults.set(launchAtLogin, forKey: Key.launchAtLogin.rawValue)
        defaults.set(appearanceMode.rawValue, forKey: Key.appearanceMode.rawValue)
    }

    private static func loadShortcut(_ defaults: UserDefaults) -> KeyCombo? {
        guard let data = defaults.data(forKey: Key.shortcut.rawValue) else { return nil }
        return try? JSONDecoder().decode(KeyCombo.self, from: data)
    }

    // MARK: - Launch at login

    private static var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// `SMAppService` only works for a real, signed app bundle; when running the
    /// raw binary out of a build directory the request fails and the toggle
    /// reverts to the truth.
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
            persist()
        } catch {
            NSLog("[GuacTerm] launch at login failed: \(error.localizedDescription)")
            launchAtLogin = Self.isLaunchAtLoginEnabled
        }
    }

    // MARK: - System discovery

    static var accountLoginShell: String {
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

        if let contents = try? String(contentsOfFile: "/etc/shells", encoding: .utf8) {
            candidates += contents
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        }

        // Resolved against `PATH`, so this covers Homebrew on Apple silicon
        // (`/opt/homebrew/bin`) as well as Intel and manual installs. A name that
        // is not installed never appears.
        candidates += ["fish", "nu", "tmux", "zellij"].compactMap(resolveExecutable)

        var seen = Set<String>()
        return candidates.compactMap(resolveExecutable).filter { seen.insert($0).inserted }
    }

    static var defaultFontName: String {
        let families = NSFontManager.shared.availableFontFamilies
        if families.contains("SF Mono") {
            return "SF Mono"
        }
        if families.contains("Menlo") {
            return "Menlo"
        }
        return "Monaco"
    }

    /// Installed fixed-pitch families, the only set that makes sense for a
    /// terminal grid.
    static var availableFontFamilies: [String] {
        let manager = NSFontManager.shared
        return manager.availableFontFamilies
            .filter { family in
                guard let font = manager.font(withFamily: family, traits: [], weight: 5, size: 12) else {
                    return false
                }
                return font.isFixedPitch
            }
            .sorted()
    }
}
