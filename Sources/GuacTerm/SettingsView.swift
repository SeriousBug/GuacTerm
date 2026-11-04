import AppKit
import SwiftUI

/// The contents of the settings window: one scrolling column of grouped rows,
/// designed for a fixed content size of 560 x 660.
///
/// Every control reads and writes ``Settings`` directly, so there is no "Apply"
/// button and no second copy of the configuration to keep in sync.
struct SettingsView: View {

    @ObservedObject var settings: Settings

    /// Building these lists is expensive — `NSFontManager` enumerates every
    /// installed family — so they are read once when the pane appears.
    @State private var shellPaths: [String] = []
    @State private var fontFamilies: [String] = []

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
        .onAppear(perform: loadSystemLists)
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

            row("Shell", caption: settings.shellPath) {
                shellControls
            }
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

            row(
                "Hide When Focus Is Lost",
                caption: "Drop the terminal away when you switch to another app."
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
        }
    }

    /// Label on the left, control right-aligned, optional caption underneath.
    private func row<Control: View>(
        _ title: String,
        caption: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 16) {
                Text(title)
                    .fixedSize()
                Spacer(minLength: 12)
                control()
            }
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var themeRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Text("Theme")
                    .fixedSize()
                Spacer(minLength: 12)
                Picker("Theme", selection: $settings.themeID) {
                    ForEach(TerminalTheme.catalog) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            ThemePreview(theme: settings.theme)
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Controls

    private var shellControls: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(shellOptions, id: \.self) { path in
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
                Text(shellName)
            }
            .fixedSize()

            Button("Choose…", action: chooseShell)
        }
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

    /// `shellPath` may point outside `/etc/shells` (an old value, or a file
    /// picked with "Choose…"), so the current one is always an option.
    private var shellOptions: [String] {
        var paths = shellPaths
        if !paths.contains(settings.shellPath) {
            paths.insert(settings.shellPath, at: 0)
        }
        return paths
    }

    private var shellName: String {
        let name = (settings.shellPath as NSString).lastPathComponent
        return name.isEmpty ? "Shell" : name
    }

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

    // MARK: - Actions

    private func chooseShell() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Shell"
        panel.message = "Pick the program GuacTerm runs for new sessions."
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.treatsFilePackagesAsDirectories = false
        panel.showsHiddenFiles = true

        let directory = (settings.shellPath as NSString).deletingLastPathComponent
        panel.directoryURL = URL(fileURLWithPath: directory.isEmpty ? "/bin" : directory)

        // The delegate is only weakly held by the panel, so keep it alive for
        // the duration of the modal session.
        let filter = ExecutableFileFilter()
        panel.delegate = filter
        let response = withExtendedLifetime(filter) { panel.runModal() }

        guard response == .OK, let url = panel.url else { return }
        if FileManager.default.isExecutableFile(atPath: url.path) {
            settings.shellPath = url.path
        } else {
            NSSound.beep()
        }
    }
}

// MARK: - Shell picker filter

/// Lets the open panel walk into folders but only enables files that can be
/// executed, which is the only kind of file that makes sense as a shell.
@MainActor
private final class ExecutableFileFilter: NSObject, NSOpenSavePanelDelegate {

    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if exists, isDirectory.boolValue { return true }
        return FileManager.default.isExecutableFile(atPath: url.path)
    }
}

// MARK: - Theme preview

/// A live sample of the selected ``TerminalTheme``: ANSI palette, a prompt line
/// and the cursor block, on the theme's own background.
private struct ThemePreview: View {

    let theme: TerminalTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 3) {
                        ForEach(0..<8, id: \.self) { column in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(swatch(row * 8 + column))
                                .frame(width: 16, height: 9)
                        }
                    }
                }
            }

            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color(nsColor: theme.nsCursor))
                    .frame(width: 7, height: 13)
                Text("‾/code/guacterm → make run")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(nsColor: theme.nsForeground))
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: theme.nsBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the \(theme.name) theme")
    }

    private func swatch(_ index: Int) -> Color {
        let palette = theme.nsAnsi
        guard palette.indices.contains(index) else {
            return Color(nsColor: theme.nsForeground)
        }
        return Color(nsColor: palette[index])
    }
}
