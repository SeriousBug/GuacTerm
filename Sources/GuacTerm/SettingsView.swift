import AppKit
import SwiftUI

/// The contents of the settings window: one scrolling column of grouped rows,
/// designed for a fixed content size of 560 x 660.
///
/// Every control reads and writes ``Settings`` directly, so there is no "Apply"
/// button and no second copy of the configuration to keep in sync.
struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var library: ThemeLibrary
    @ObservedObject var updater: Updater

    /// Opens the theme sheet as soon as the pane appears, so the picker can be
    /// reached from the `--theme-picker` launch flag (and from screenshots).
    var showsThemePickerOnAppear = false

    /// Building these lists is expensive — `NSFontManager` enumerates every
    /// installed family — so they are read once when the pane appears.
    @State private var shellPaths: [String] = []
    @State private var fontFamilies: [String] = []

    /// Presents ``ThemePicker`` as a sheet.
    @State private var showingThemePicker = false

    private let padding: CGFloat = 22

    // MARK: - Body

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                    .padding(.top, 16)
                rows
                footer
            }
            .padding(.horizontal, padding)
            .padding(.top, 20)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            loadSystemLists()
            if showsThemePickerOnAppear {
                showingThemePicker = true
            }
        }
        .sheet(isPresented: $showingThemePicker) {
            ThemePicker(settings: settings, library: library)
        }
    }

    // MARK: - Header and footer

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(AppInfo.name)
                .font(.largeTitle.weight(.semibold))
            Text(AppInfo.tagline)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("No tabs. No splits. Run tmux or zellij inside the terminal.")
            Text(AppInfo.versionDescription)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 20)
    }

    // MARK: - Rows

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            shortcutRow
            Divider()

            shellRow
            Divider()

            row("Scrollback", caption: "Applies to the next session.") {
                scrollbackControls
            }
            Divider()

            row("Window Height") {
                heightControls
            }
            Divider()

            row("Font") {
                fontControls
            }
            Divider()

            row(
                "Appearance",
                caption: "Terminal colors come from the theme below."
            ) {
                Picker("Appearance", selection: $settings.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
            Divider()

            themeRow
            Divider()

            glassRows
            Divider()

            row(
                "Hide When Focus Is Lost",
                caption: """
                Drop the terminal away when you switch to another app. While Settings \
                is open it stays put, so changes can be previewed.
                """
            ) {
                Toggle("Hide When Focus Is Lost", isOn: $settings.hideOnFocusLoss)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            Divider()

            row("Launch at Login", caption: "Start GuacTerm when you log in.") {
                Toggle("Launch at Login", isOn: launchAtLoginBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            // Absent when the bundle has no feed configured, which is what a
            // build assembled by hand looks like.
            if updater.isAvailable {
                Divider()
                UpdatesSettings(updater: updater)
            }
        }
    }

    private func row(
        _ title: String,
        caption: String? = nil,
        @ViewBuilder control: () -> some View
    ) -> some View {
        SettingsRow(title: title, caption: caption, control: control)
    }

    private var shortcutRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 16) {
                Text("Toggle Shortcut")
                    .fixedSize()
                Spacer(minLength: 12)
                ShortcutRecorder(combo: $settings.shortcut)
            }
            if let issue = settings.shortcutIssue {
                Label(issue, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The catalog holds ~890 schemes, so the menu is only ever a button: the
    /// list itself lives in the ``ThemePicker`` sheet, which is also where a
    /// theme is imported from a `.itermcolors` file.
    private var themeRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Text("Theme")
                    .fixedSize()
                Spacer(minLength: 12)
                Button {
                    showingThemePicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text(settings.theme.name)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .help("Browse all \(library.all.count) themes, or import your own")
            }

            ThemePreview(theme: settings.theme)
                .contentShape(Rectangle())
                .onTapGesture { showingThemePicker = true }
                .help("Browse all \(library.all.count) themes, or import your own")
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Liquid Glass needs macOS 26, so on older systems these rows are simply
    /// absent rather than shown greyed out.
    @ViewBuilder
    private var glassRows: some View {
        if Settings.glassIsSupported {
            VStack(alignment: .leading, spacing: 0) {
                row(
                    "Liquid Glass",
                    caption: settings.glassBackground
                        ? """
                        The theme is painted over macOS's glass material, \
                        so the desktop shows through as it moves behind it.
                        """
                        : "Put the terminal on macOS's Liquid Glass material instead of a solid background."
                ) {
                    Toggle("Liquid Glass", isOn: $settings.glassBackground)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                if settings.glassBackground {
                    Divider()
                    row(
                        "Glass Tint",
                        caption: """
                        How much of the theme covers the glass. Lower shows more of the desktop, \
                        and is harder to read on busy backgrounds.
                        """
                    ) {
                        HStack(spacing: 10) {
                            Slider(value: glassTintBinding, in: Settings.Limits.glassTint)
                                .frame(width: 190)
                            Text(settings.glassTint, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Controls

    /// A typed program beats a file picker: `zsh` or `zellij` is faster to type
    /// than finding `/opt/homebrew/bin/zellij` in a panel full of dotfiles, and
    /// a bare name is looked up in `PATH` by ``Settings/resolveExecutable(_:)``.
    /// The field also takes a whole command line — `zellij attach || zellij` —
    /// which ``Settings/shellLaunch`` hands to a shell. The menu next to the
    /// field lists only programs that are installed.
    private var shellRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 12) {
                Text("Shell")
                    .fixedSize()
                Spacer(minLength: 12)

                TextField("/bin/zsh", text: $settings.shellPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .frame(width: 230)
                    .help("A program like zsh or zellij, or a command line like zellij attach || zellij.")

                Menu {
                    ForEach(shellPaths, id: \.self) { path in
                        Button {
                            settings.shellPath = path
                        } label: {
                            if path == settings.shellPath {
                                Label(path, systemImage: "checkmark")
                            } else {
                                Text(path)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Installed shells and multiplexers")
            }

            if let warning = shellWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                captionText(shellSummary)
            }
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Spells out what the Shell field will actually start, because a typed
    /// command line runs through a shell rather than being exec'd itself.
    private var shellSummary: String {
        if settings.shellLine.isEmpty {
            return "Empty, so \(Settings.accountLoginShell) is used."
        }
        switch settings.shellLaunch {
        case let .program(program):
            return "Runs \(program) as a login shell. Applies to the next session."
        case let .command(shell, _):
            return "A command line, so \(shell) -c runs it. Applies to the next session."
        }
    }

    private var shellWarning: String? {
        guard settings.shellIsUninstalledProgram else { return nil }
        let name = settings.shellLine
        return "\(name) is not an installed program. \(Settings.accountLoginShell) still runs it with -c, so it has to be something your startup files define."
    }

    private func captionText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var scrollbackControls: some View {
        HStack(spacing: 6) {
            TextField("Lines", value: scrollbackBinding, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 88)
            Stepper(
                "Scrollback lines",
                value: scrollbackBinding,
                in: Settings.Limits.scrollback,
                step: 1000
            )
            .labelsHidden()
            Text("lines")
                .foregroundStyle(.secondary)
        }
    }

    private var heightControls: some View {
        HStack(spacing: 10) {
            Slider(value: heightBinding, in: Settings.Limits.height)
                .frame(width: 190)
            Text(settings.heightFraction, format: .percent.precision(.fractionLength(0)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }

    private var fontControls: some View {
        HStack(spacing: 10) {
            Picker("Font", selection: $settings.fontName) {
                ForEach(fontOptions, id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(minWidth: 120, idealWidth: 140, maxWidth: 160)

            Slider(value: fontSizeBinding, in: Settings.Limits.fontSize, step: 1)
                .frame(width: 130)

            Text("\(Int(settings.fontSize.rounded())) pt")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }

    // MARK: - Bindings

    private var scrollbackBinding: Binding<Int> {
        Binding(
            get: { settings.scrollbackLines },
            set: { settings.scrollbackLines = Self.clamp($0, to: Settings.Limits.scrollback) }
        )
    }

    private var heightBinding: Binding<Double> {
        Binding(
            get: { settings.heightFraction },
            set: { settings.heightFraction = Self.clamp($0, to: Settings.Limits.height) }
        )
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { settings.fontSize },
            set: { settings.fontSize = Self.clamp($0, to: Settings.Limits.fontSize) }
        )
    }

    private var glassTintBinding: Binding<Double> {
        Binding(
            get: { settings.glassTint },
            set: { settings.glassTint = Self.clamp($0, to: Settings.Limits.glassTint) }
        )
    }

    /// `ClosedRange.clamped(to:)` is not public API, so the limits are applied
    /// by hand: a hand-edited `defaults write` must not reach the terminal.
    private static func clamp<Value: Comparable>(
        _ value: Value,
        to limits: ClosedRange<Value>
    ) -> Value {
        min(max(value, limits.lowerBound), limits.upperBound)
    }

    /// `launchAtLogin` is `private(set)`: the system's registration has to be
    /// updated through `Settings`, so the toggle writes through this binding.
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { settings.setLaunchAtLogin($0) }
        )
    }

    // MARK: - Lists

    private var fontOptions: [String] {
        var families = fontFamilies
        if !families.contains(settings.fontName) {
            families.insert(settings.fontName, at: 0)
        }
        return families
    }

    private func loadSystemLists() {
        if shellPaths.isEmpty {
            shellPaths = Settings.availableShells
        }
        if fontFamilies.isEmpty {
            fontFamilies = Settings.availableFontFamilies
        }
    }
}
