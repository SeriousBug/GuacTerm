import AppKit
import ServiceManagement

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

    /// What `$SHELL` names inside the session.
    ///
    /// That is the shell that is running, not the program that was launched:
    /// a multiplexer reads `$SHELL` to decide what to start in a new pane or
    /// window, so calling zellij the user's shell makes zellij start zellij.
    /// This only ever reaches the child process; the account's own login shell
    /// in the user database is never touched.
    var announcedShell: String {
        switch self {
        case let .program(program):
            Settings.isShell(program) ? program : Settings.accountLoginShell
        case let .command(shell, _):
            shell
        }
    }
}

/// Everything the user can change, persisted in `UserDefaults`.
///
/// This is deliberately the *entire* configuration surface of the app. GuacTerm
/// has no tabs, no splits, no profiles and no plugins: if you want those, run
/// tmux or zellij inside the terminal.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    /// Ranges enforced by the UI and re-checked on load, so a hand-edited
    /// `defaults write` cannot produce a window taller than the screen, a font
    /// the terminal cannot lay a grid out with, or a scrollback big enough to
    /// cost real memory.
    enum Limits {
        static let scrollback = 0 ... 1_000_000
        static let height = 0.15 ... 1.0
        static let fontSize = 8.0 ... 48.0
        /// Below 20% the theme is barely there and text stops being readable.
        static let glassTint = 0.2 ... 1.0

        /// `ClosedRange.clamped(to:)` is not public API, so the limits are
        /// applied by hand.
        static func clamp<Value: Comparable>(_ value: Value, to limits: ClosedRange<Value>) -> Value {
            min(max(value, limits.lowerBound), limits.upperBound)
        }
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

    /// Identifier of the `TerminalTheme` used while the appearance is dark.
    @Published var darkThemeID: String {
        didSet {
            persist()
            onAppearanceChange?()
        }
    }

    /// Identifier of the `TerminalTheme` used while the appearance is light.
    @Published var lightThemeID: String {
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

    /// Look of GuacTerm's windows and menus, and of the terminal.
    @Published var appearanceMode: AppearanceMode {
        didSet {
            persist()
            // The chrome first: which scheme the terminal should paint is read
            // back from the appearance this sets.
            onAppearanceModeChange?(appearanceMode)
            onAppearanceChange?()
        }
    }

    /// Drop the terminal away when another app takes focus.
    @Published var hideOnFocusLoss: Bool {
        didSet { persist() }
    }

    /// How much of the theme background is painted over the Liquid Glass
    /// material: 1 is fully opaque, which is how the glass is switched off.
    /// Ignored on systems without `NSGlassEffectView`.
    @Published var glassTint: Double {
        didSet {
            persist()
            onAppearanceChange?()
        }
    }

    /// True only when the system can draw Liquid Glass and the tint leaves
    /// something of it showing.
    var usesGlass: Bool {
        Self.glassIsSupported && glassTint < 1
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

    /// The scheme the appearance puts in effect right now.
    var theme: TerminalTheme {
        theme(for: themeSlot)
    }

    /// Which of the two schemes the appearance puts in effect.
    var themeSlot: ThemeSlot {
        switch appearanceMode {
        case .dark: .dark
        case .light: .light
        case .system: Self.systemIsDark ? .dark : .light
        }
    }

    /// True while the system GuacTerm follows is drawing in dark mode.
    ///
    /// The app's own effective appearance rather than a defaults lookup: it is
    /// what the windows around the terminal already use, and it carries a
    /// forced appearance when the user picked one.
    private static var systemIsDark: Bool {
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// The identifier selected for a slot.
    func themeID(for slot: ThemeSlot) -> String {
        switch slot {
        case .light: lightThemeID
        case .dark: darkThemeID
        }
    }

    /// Selects the scheme for one slot.
    func setThemeID(_ id: String, for slot: ThemeSlot) {
        switch slot {
        case .light: lightThemeID = id
        case .dark: darkThemeID = id
        }
    }

    /// A slot's scheme, resolved against the bundled catalog *and* the schemes
    /// the user imported, falling back to that slot's default when the
    /// identifier points at a theme whose file has since been removed.
    func theme(for slot: ThemeSlot) -> TerminalTheme {
        ThemeLibrary.shared.theme(id: themeID(for: slot), fallback: slot.defaultThemeID)
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
        case darkThemeID
        case lightThemeID
        /// The single scheme older versions stored. Read once to seed the two
        /// slots and never written again.
        case legacyThemeID = "themeID"
        case heightFraction
        case fontName
        case fontSize
        case hideOnFocusLoss
        case glassTint
        /// The switch Liquid Glass used to have. Read once, then removed.
        case legacyGlassBackground = "glassBackground"
        case launchAtLogin
        case appearanceMode
    }

    private let defaults: UserDefaults
    private var isLoading = false

    /// Identifies this model's registration with ``ThemeLibrary/shared``, so it
    /// can be withdrawn again in ``deinit``.
    private var themeChangeToken: UUID?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isLoading = true

        shortcut = Self.loadShortcut(defaults) ?? .default
        shellPath = defaults.string(forKey: Key.shellPath.rawValue) ?? Self.accountLoginShell
        scrollbackLines = Self.loadedInt(
            defaults, .scrollbackLines, limits: Limits.scrollback, fallback: 10000
        )

        // A single scheme was stored before there were two slots. It goes to the
        // slot it was picked for, which is what leaves the other one at its
        // default instead of opening dark mode in a white terminal.
        let legacyThemeID = defaults.string(forKey: Key.legacyThemeID.rawValue)
        let legacyIsLight = legacyThemeID.map { ThemeLibrary.shared.theme(id: $0).isLight } ?? false
        darkThemeID = defaults.string(forKey: Key.darkThemeID.rawValue)
            ?? (legacyIsLight ? nil : legacyThemeID)
            ?? ThemeSlot.dark.defaultThemeID
        lightThemeID = defaults.string(forKey: Key.lightThemeID.rawValue)
            ?? (legacyIsLight ? legacyThemeID : nil)
            ?? ThemeSlot.light.defaultThemeID

        heightFraction = Self.loadedDouble(
            defaults, .heightFraction, limits: Limits.height, fallback: 0.45
        )
        fontName = defaults.string(forKey: Key.fontName.rawValue) ?? Self.defaultFontName
        fontSize = Self.loadedDouble(
            defaults, .fontSize, limits: Limits.fontSize, fallback: 13
        )
        hideOnFocusLoss = defaults.object(forKey: Key.hideOnFocusLoss.rawValue) as? Bool ?? true

        // Liquid Glass used to be a switch with a tint of its own. The tint is
        // now the switch, so a terminal that had the glass turned off is given a
        // fully opaque one rather than being repainted with an effect the user
        // declined. The old key is consumed here, so the slider decides alone
        // from this launch on.
        let legacyGlass = defaults.object(forKey: Key.legacyGlassBackground.rawValue) as? Bool
        var tint = Self.loadedDouble(
            defaults, .glassTint, limits: Limits.glassTint, fallback: 0.65
        )
        if legacyGlass == false {
            tint = Limits.glassTint.upperBound
            defaults.set(tint, forKey: Key.glassTint.rawValue)
        }
        if legacyGlass != nil {
            defaults.removeObject(forKey: Key.legacyGlassBackground.rawValue)
        }
        glassTint = tint
        appearanceMode = defaults
            .string(forKey: Key.appearanceMode.rawValue)
            .flatMap(AppearanceMode.init(rawValue:)) ?? .system
        launchAtLogin = Self.isLaunchAtLoginEnabled

        isLoading = false

        // A theme can change without an identifier changing (an imported file
        // replaced by an updated copy) and can disappear entirely (its file
        // moved to the Trash), so repaints follow the library rather than the
        // identifiers alone.
        themeChangeToken = ThemeLibrary.shared.onChange { [weak self] in
            self?.onAppearanceChange?()
        }
    }

    isolated deinit {
        // The library outlives this model, so the registration has to be given
        // back rather than left pointing at a `self` that is gone.
        guard let themeChangeToken else { return }
        ThemeLibrary.shared.removeOnChange(themeChangeToken)
    }

    private func persist() {
        guard !isLoading else { return }
        defaults.set(try? JSONEncoder().encode(shortcut), forKey: Key.shortcut.rawValue)
        defaults.set(shellPath, forKey: Key.shellPath.rawValue)
        defaults.set(scrollbackLines, forKey: Key.scrollbackLines.rawValue)
        defaults.set(darkThemeID, forKey: Key.darkThemeID.rawValue)
        defaults.set(lightThemeID, forKey: Key.lightThemeID.rawValue)
        defaults.set(heightFraction, forKey: Key.heightFraction.rawValue)
        defaults.set(fontName, forKey: Key.fontName.rawValue)
        defaults.set(fontSize, forKey: Key.fontSize.rawValue)
        defaults.set(hideOnFocusLoss, forKey: Key.hideOnFocusLoss.rawValue)
        defaults.set(glassTint, forKey: Key.glassTint.rawValue)
        defaults.set(launchAtLogin, forKey: Key.launchAtLogin.rawValue)
        defaults.set(appearanceMode.rawValue, forKey: Key.appearanceMode.rawValue)
    }

    /// A stored number brought back inside `limits`, or `fallback` when the key
    /// holds nothing usable.
    ///
    /// The finite check is the part that is easy to miss: `min` and `max` hand
    /// NaN straight back, so a height stored as `nan` would survive them, size
    /// the panel to the whole screen, and leave no slider able to undo it.
    private static func loadedDouble(
        _ defaults: UserDefaults,
        _ key: Key,
        limits: ClosedRange<Double>,
        fallback: Double
    ) -> Double {
        guard let stored = defaults.object(forKey: key.rawValue) as? Double,
              stored.isFinite
        else { return fallback }
        return Limits.clamp(stored, to: limits)
    }

    private static func loadedInt(
        _ defaults: UserDefaults,
        _ key: Key,
        limits: ClosedRange<Int>,
        fallback: Int
    ) -> Int {
        guard let stored = defaults.object(forKey: key.rawValue) as? Int else { return fallback }
        return Limits.clamp(stored, to: limits)
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
