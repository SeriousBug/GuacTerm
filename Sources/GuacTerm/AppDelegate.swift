import AppKit
import UniformTypeIdentifiers

/// Wires together the pieces: menu bar item, global shortcut, the drop-down
/// terminal and the settings window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings.shared
    private let themes = ThemeLibrary.shared
    private let hotKey = GlobalHotKey()

    private var terminal: TerminalController!
    private var settingsWindowController: SettingsWindowController?
    private var statusItem: NSStatusItem?

    /// Set when a theme was imported from a file opened with the app before
    /// launch finished, when there was no window to show it in yet.
    private var opensSettingsAfterLaunch = false

    // MARK: - Launch

    func applicationDidFinishLaunching(_: Notification) {
        buildMainMenu()
        terminal = TerminalController(settings: settings)

        settings.onShortcutChange = { [weak self] _ in
            self?.applyShortcut()
        }
        settings.onAppearanceModeChange = { [weak self] _ in
            self?.applyAppearanceMode()
        }
        applyAppearanceMode()

        hotKey.onPress = { [weak self] in
            self?.toggleTerminal()
        }
        applyShortcut()
        configureStatusItem()

        // Show the terminal the first time the app runs so the product
        // introduces itself. Afterwards it stays out of the way.
        let defaults = UserDefaults.standard
        let launchedBefore = defaults.bool(forKey: "GuacTermHasLaunchedBefore")
        defaults.set(true, forKey: "GuacTermHasLaunchedBefore")

        // Two launch flags: `--show` drops the terminal down (and is what a
        // first run does anyway), `--settings` opens the pane instead, which is
        // how you get to it without hunting for the menu bar item.
        if CommandLine.arguments.contains("--settings") {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                self.openSettings()
            }
        } else if !launchedBefore || CommandLine.arguments.contains("--show") {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                self.terminal.show()
            }
        }

        if opensSettingsAfterLaunch {
            opensSettingsAfterLaunch = false
            openSettings()
        }
    }

    func applicationWillTerminate(_: Notification) {
        hotKey.unregister()
        terminal.shutdown()
    }

    func applicationDidResignActive(_: Notification) {
        terminal.handleApplicationDeactivated()
    }

    // MARK: - Terminal

    @objc private func toggleTerminal() {
        terminal.toggle()
    }

    @objc private func showTerminal() {
        terminal.show()
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: AppInfo.name,
            .applicationVersion: AppInfo.version,
            .version: AppInfo.build,
        ])
    }

    // MARK: - Importing themes

    /// Import from the menu bar, for a theme that is not going to be dragged
    /// onto the picker.
    @objc private func importTheme() {
        let panel = NSOpenPanel()
        panel.title = "Import iTerm2 Theme"
        panel.prompt = "Import"
        panel.message = "Choose one or more .\(ITermColors.pathExtension) files."
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: ITermColors.pathExtension) ?? .data,
        ]

        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        importThemes(from: panel.urls)
    }

    /// A `.itermcolors` file opened with GuacTerm, from the Finder or with
    /// `open -a GuacTerm scheme.itermcolors`. This is why the bundle declares the
    /// type (see project.yml) — double-clicking a scheme is the shortest path
    /// there is.
    func application(_: NSApplication, open urls: [URL]) {
        importThemes(from: urls)
    }

    private func importThemes(from urls: [URL]) {
        let summary = themes.importThemes(from: urls)
        if let id = summary.firstImportedID {
            settings.themeID = id
        }

        guard !summary.failures.isEmpty else {
            // Show the pane so the new theme is visible where it was imported
            // to. When a file arrives before launch has finished there is no
            // terminal to show it against yet, so the window opens at the end of
            // `applicationDidFinishLaunching` instead.
            if summary.firstImportedID != nil {
                if terminal == nil {
                    opensSettingsAfterLaunch = true
                } else {
                    openSettings()
                }
            }
            return
        }

        let alert = NSAlert()
        alert.messageText = summary.importedNames.isEmpty
            ? "Could not import the theme"
            : "Some themes were not imported"
        alert.informativeText = summary.message
        alert.alertStyle = .warning
        NSApp.activate()
        alert.runModal()
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            let controller = SettingsWindowController(
                settings: settings,
                showsThemePickerOnAppear: CommandLine.arguments.contains("--theme-picker")
            )
            controller.onClose = { [weak self] in
                self?.terminal.setSettingsPreviewing(false)
            }
            settingsWindowController = controller
        }

        // The pane is also the preview: the terminal stays (or comes) up, and
        // is dropped below the settings window before that window is ordered
        // in front of it.
        terminal.setSettingsPreviewing(true)
        settingsWindowController?.place(clearOf: terminal.frameOnScreen)

        NSApp.activate()
        settingsWindowController?.showWindow(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Shortcut

    private func applyShortcut() {
        do {
            try hotKey.register(settings.shortcut)
            settings.shortcutIssue = nil
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            settings.shortcutIssue = message
            NSLog("[GuacTerm] could not register shortcut: \(message)")
        }
        updateStatusItemToolTip()
    }

    // MARK: - Appearance

    /// Applied to the whole app so the settings window, menus and the panel all
    /// agree. `nil` hands control back to the system setting.
    private func applyAppearanceMode() {
        NSApp.appearance = settings.appearanceMode.nsAppearance
    }

    // MARK: - Menu bar

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.behavior = .removalAllowed

        if let button = item.button {
            let image = NSImage(
                systemSymbolName: "apple.terminal",
                accessibilityDescription: AppInfo.name
            ) ?? NSImage(
                systemSymbolName: "terminal",
                accessibilityDescription: AppInfo.name
            )
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        statusItem = item
        updateStatusItemToolTip()
    }

    private func updateStatusItemToolTip() {
        statusItem?.button?.toolTip = "\(AppInfo.name) — \(settings.shortcut.displayString)"
    }

    @objc private func statusItemClicked(_: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            presentStatusMenu()
        } else {
            toggleTerminal()
        }
    }

    private func presentStatusMenu() {
        guard let statusItem else { return }

        let menu = NSMenu()
        menu.addItem(
            item(
                titled: terminal.isShown ? "Hide \(AppInfo.name)" : "Show \(AppInfo.name)",
                action: #selector(showTerminal),
                keyEquivalent: ""
            )
        )
        menu.addItem(.separator())
        menu.addItem(item(titled: "Import Theme…", action: #selector(importTheme), keyEquivalent: ""))
        menu.addItem(item(titled: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(item(titled: "Quit \(AppInfo.name)", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func item(titled title: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    /// Without an Edit menu, ⌘C and ⌘V never reach the terminal: AppKit routes
    /// those key equivalents through the main menu, not to the focused view.
    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(item(titled: "About \(AppInfo.name)", action: #selector(showAbout), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(item(titled: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(item(titled: "Hide \(AppInfo.name)", action: #selector(toggleTerminal), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(item(titled: "Quit \(AppInfo.name)", action: #selector(quit), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        let undo = NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        undo.target = nil
        editMenu.addItem(undo)
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redo.target = nil
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(
            NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        )
        editMenu.addItem(
            NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        )
        editMenu.addItem(
            NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        )
        editMenu.addItem(
            NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        )
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }
}
