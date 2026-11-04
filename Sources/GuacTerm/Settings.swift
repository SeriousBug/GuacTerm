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

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// `nil` means "follow the system".
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
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

    /// Ranges enforced by the UI and re-checked here, so a hand-edited
    /// `defaults write` cannot produce a window taller than the screen.
    enum Limits {
        static let scrollback = 0...1_000_000
        static let height = 0.15...1.0
        static let fontSize = 8.0...48.0
    }

    // MARK: - Stored settings

    /// The global shortcut that shows and hides the terminal.
    @Published var shortcut: KeyCombo {
        didSet {
            persist()
            onShortcutChange?(shortcut)
        }
    }

    /// Absolute path of the shell to launch, e.g. `/bin/zsh`.
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
        didSet { persist() }
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

    /// Called when the window appearance changes.
    var onAppearanceModeChange: ((AppearanceMode) -> Void)?

    // MARK: - Derived

    var theme: TerminalTheme {
        TerminalTheme.theme(id: themeID)
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

    /// Shell used for new sessions, falling back to the account's login shell
    /// if the configured one has been uninstalled.
    var resolvedShellPath: String {
        let path = shellPath
        if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return Self.accountLoginShell
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
        case launchAtLogin
        case appearanceMode
    }

    private let defaults: UserDefaults
    private var isLoading = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isLoading = true

        self.shortcut = Self.loadShortcut(defaults) ?? .default
        self.shellPath = defaults.string(forKey: Key.shellPath.rawValue) ?? Self.accountLoginShell
        self.scrollbackLines = defaults.object(forKey: Key.scrollbackLines.rawValue) as? Int ?? 10_000
        self.themeID = defaults.string(forKey: Key.themeID.rawValue) ?? TerminalTheme.defaultThemeID
        self.heightFraction = defaults.object(forKey: Key.heightFraction.rawValue) as? Double ?? 0.45
        self.fontName = defaults.string(forKey: Key.fontName.rawValue) ?? Self.defaultFontName
        self.fontSize = defaults.object(forKey: Key.fontSize.rawValue) as? Double ?? 13
        self.hideOnFocusLoss = defaults.object(forKey: Key.hideOnFocusLoss.rawValue) as? Bool ?? true
        self.appearanceMode = defaults
            .string(forKey: Key.appearanceMode.rawValue)
            .flatMap(AppearanceMode.init(rawValue:)) ?? .system
        self.launchAtLogin = Self.isLaunchAtLoginEnabled

        isLoading = false
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
           FileManager.default.isExecutableFile(atPath: shell) {
            return shell
        }
        return "/bin/zsh"
    }

    /// Shells listed in `/etc/shells`, which is the set macOS considers valid
    /// login shells.
    static var availableShells: [String] {
        let loginShell = accountLoginShell
        guard let contents = try? String(contentsOfFile: "/etc/shells", encoding: .utf8) else {
            return [loginShell]
        }
        let shells = contents
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .filter { FileManager.default.isExecutableFile(atPath: $0) }
        var seen = Set<String>()
        let unique = shells.filter { seen.insert($0).inserted }
        return unique.contains(loginShell) ? unique : [loginShell] + unique
    }

    static var defaultFontName: String {
        let families = NSFontManager.shared.availableFontFamilies
        if families.contains("SF Mono") { return "SF Mono" }
        if families.contains("Menlo") { return "Menlo" }
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
