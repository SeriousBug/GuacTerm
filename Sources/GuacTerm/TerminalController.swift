import AppKit
import SwiftTerm

/// Owns the drop-down window and the single shell running inside it.
///
/// GuacTerm has exactly one terminal. When the user hides the panel the shell
/// keeps running, which is the whole point of a drop-down terminal: the history
/// and the working directory are still there when you come back.
@MainActor
final class TerminalController: NSObject {
    private enum Timing {
        static let show: TimeInterval = 0.18
        static let hide: TimeInterval = 0.14
        /// Ignore focus flicker caused by activation itself.
        static let deactivationGrace: TimeInterval = 0.25
    }

    private let settings: Settings
    private let panel: DropDownPanel
    private let container = DropDownContainerView(frame: .zero)

    private var terminalView: GuacTerminalView?
    private var sessionAlive = false
    private var needsFreshSession = false

    /// The Liquid Glass material behind the terminal. Typed as `NSView` because
    /// the concrete class only exists on macOS 26 and this property cannot carry
    /// an availability attribute.
    private var glassView: NSView?

    /// Holder for the terminal view. It is what moves between the container and
    /// the glass effect's `contentView`, so the terminal's own view is created
    /// once and never re-parented behind SwiftTerm's back.
    private let terminalHost: NSView = {
        let view = NSView(frame: .zero)
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true
        return view
    }()

    private var visible = false
    private var animationGeneration = 0
    private var shownAt: Date?
    private var previousApplication: NSRunningApplication?

    /// True while the settings window is open. The pane is also the live
    /// preview, so the panel stays on screen while it is up: it ignores "Hide
    /// When Focus Is Lost" and drops below the settings window instead of
    /// hanging above it.
    private var isSettingsPreviewing = false

    var isShown: Bool {
        visible
    }

    /// The panel's frame on screen while it is resting there, or `nil` while it
    /// is away. The settings window uses it to stay out of the terminal's way,
    /// so it reports the frame the panel is heading for rather than wherever a
    /// running slide happens to be.
    var frameOnScreen: NSRect? {
        guard visible, let screen = targetScreen() else { return nil }
        return frame(for: screen)
    }

    init(settings: Settings) {
        self.settings = settings
        panel = DropDownPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 500),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()

        configurePanel()
        configureChangeHandling()
    }

    private func configurePanel() {
        container.autoresizingMask = [.width, .height]
        panel.contentView = container
        attachTerminalHost(to: container)
        panel.isFloatingPanel = true
        // Above normal windows, below the system's own overlays.
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.isRestorable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // A borderless window has no title bar, but the title still names the
        // window for accessibility and Mission Control.
        panel.title = AppInfo.name
    }

    private func configureChangeHandling() {
        settings.onAppearanceChange = { [weak self] in
            self?.applyAppearance()
        }
        settings.onSessionSettingsChange = { [weak self] in
            // Never kill a shell the user is working in; take effect next time.
            self?.needsFreshSession = true
        }
        settings.onWindowGeometryChange = { [weak self] in
            self?.applyWindowHeight()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    // MARK: - Show and hide

    func toggle() {
        if visible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard let screen = targetScreen() else { return }

        // Lay the window out at its final size *before* the first draw, so the
        // slide is a pure position change and the terminal never reflows (and
        // never spams the PTY with resize events) mid-animation.
        let target = frame(for: screen)
        panel.setFrame(target, display: false)
        panel.contentView?.layoutSubtreeIfNeeded()

        prepareSession()
        guard let terminalView else { return }

        let alreadyUp = visible && panel.isVisible
        if alreadyUp {
            focusTerminal()
            return
        }

        if !NSApp.isActive {
            previousApplication = NSWorkspace.shared.frontmostApplication
        }

        applyAppearance()

        animationGeneration += 1
        visible = true

        let start = NSRect(
            x: target.minX,
            y: target.maxY,
            width: target.width,
            height: target.height
        )
        panel.setFrame(start, display: false)

        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(terminalView)
        shownAt = Date()

        animate(to: target, duration: Timing.show, timing: .easeOut)
    }

    func hide(animated: Bool = true) {
        guard visible else { return }
        visible = false
        animationGeneration += 1
        let generation = animationGeneration

        let current = panel.frame
        let offscreen = NSRect(
            x: current.minX,
            y: current.maxY,
            width: current.width,
            height: current.height
        )

        // NSAnimationContext calls this on the main thread when the animation
        // ends, so hopping back onto the main actor is a statement of fact.
        let finish: @Sendable () -> Void = { [weak self] in
            MainActor.assumeIsolated {
                guard let self,
                      self.animationGeneration == generation,
                      !self.visible
                else { return }
                self.panel.orderOut(nil)
                self.panel.setFrame(offscreen, display: false)
                self.restorePreviousApplication()
            }
        }

        if animated {
            animate(to: offscreen, duration: Timing.hide, timing: .easeIn, completion: finish)
        } else {
            panel.setFrame(offscreen, display: false)
            finish()
        }
    }

    /// Called when another app becomes active. Only hides when the user asked
    /// for that behaviour in Settings, and never while the settings window is
    /// open: dropping the terminal away mid-change would make the preview
    /// impossible to look at.
    func handleApplicationDeactivated() {
        guard settings.hideOnFocusLoss, visible, !isSettingsPreviewing else { return }
        if let shownAt, Date().timeIntervalSince(shownAt) < Timing.deactivationGrace {
            return
        }
        hide()
    }

    // MARK: - Settings preview

    /// Keeps the terminal on screen while the settings window is up.
    ///
    /// Everything the pane changes already applies live through
    /// ``Settings/onAppearanceChange``; this is what leaves a terminal there to
    /// look at. The panel normally floats at `.statusBar` so it stays above
    /// other windows, but then it would cover the settings window itself, so
    /// while previewing it drops to `.normal` and the settings window is
    /// ordered in front of it.
    func setSettingsPreviewing(_ previewing: Bool) {
        guard previewing != isSettingsPreviewing else { return }
        isSettingsPreviewing = previewing
        panel.level = previewing ? .normal : .statusBar

        if previewing {
            // Show it if it was not already: there is nothing to preview
            // otherwise. A visible panel is only refocused, not re-animated.
            show()
        }
    }

    func shutdown() {
        // Quitting is not the shell exiting: drop the delegate first so the end
        // of the session does not try to slide the panel away on the way out.
        terminalView?.processDelegate = nil
        terminalView?.terminate()
    }

    // MARK: - Animation

    private func animate(
        to frame: NSRect,
        duration: TimeInterval,
        timing: CAMediaTimingFunctionName,
        completion: (@Sendable () -> Void)? = nil
    ) {
        guard duration > 0 else {
            panel.setFrame(frame, display: true)
            completion?()
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: timing)
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(frame, display: true)
        }, completionHandler: completion)
    }

    private func focusTerminal() {
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        if let terminalView {
            panel.makeFirstResponder(terminalView)
        }
        shownAt = Date()
    }

    private func restorePreviousApplication() {
        guard let previous = previousApplication else { return }
        previousApplication = nil
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard frontmost == ProcessInfo.processInfo.processIdentifier else { return }
        previous.activate()
    }

    // MARK: - Geometry

    private func targetScreen() -> NSScreen? {
        NSScreen.underMouse
    }

    private func frame(for screen: NSScreen) -> NSRect {
        let visibleFrame = screen.visibleFrame
        let height = max(
            120,
            min(visibleFrame.height, visibleFrame.height * settings.heightFraction)
        )
        return NSRect(
            x: visibleFrame.minX,
            y: visibleFrame.maxY - height,
            width: visibleFrame.width,
            height: height
        )
    }

    @objc private func screenParametersChanged() {
        guard visible, let screen = targetScreen() else { return }
        animationGeneration += 1
        panel.setFrame(frame(for: screen), display: true)
    }

    /// Follows the height slider while the settings window is open, so the
    /// window size is previewed too instead of only applying next time. SwiftTerm
    /// reflows the shell on each step, which is what a live resize does in any
    /// other terminal.
    private func applyWindowHeight() {
        guard visible, let screen = targetScreen() else { return }
        panel.setFrame(frame(for: screen), display: true)
    }

    // MARK: - Session

    private func prepareSession() {
        if terminalView == nil {
            createTerminalView()
        } else if needsFreshSession || !sessionAlive {
            recreateTerminalView()
        }
    }

    /// Image protocols are the reason a modern terminal is worth using: Claude
    /// Code, `icat`, `chafa`, `img2sixel` and friends all draw inline.
    private static func graphicsOptions(scrollback: Int) -> TerminalOptions {
        var options = TerminalOptions(cursorStyle: .blinkBlock)
        options.scrollback = max(Settings.Limits.scrollback.lowerBound, scrollback)
        options.termName = "xterm-256color"

        // Sixel (DEC DCS). On by default in SwiftTerm; stated here so it is
        // obvious that it is a feature we intend to keep.
        options.enableSixelReported = true

        // Kitty graphics. The default budget is 10 MB per screen and local
        // transfer media are refused; both are too tight for real use, so give
        // programs the same room kitty and Ghostty do.
        options.kittyGraphics = KittyGraphicsConfiguration(
            storageLimitBytesPerScreen: 64 * 1024 * 1024,
            localMediaPolicy: .all,
            trustedTemporaryDirectory: FileManager.default.temporaryDirectory
        )

        // OSC 52 payloads and OSC 1337 inline files arrive as one OSC command,
        // so the ceiling has to be generous enough for a screenshot.
        options.maximumOscBytes = 64 * 1024 * 1024

        // Kitty's newer OSC 5522 clipboard protocol (tmux 3.4+, kitty tools).
        options.kittyClipboardPolicy = .all

        return options
    }

    private func createTerminalView() {
        let options = Self.graphicsOptions(scrollback: settings.scrollbackLines)

        let bounds = container.bounds.size.width > 1
            ? container.bounds
            : NSRect(x: 0, y: 0, width: 1200, height: 480)

        let view = GuacTerminalView(frame: bounds, font: settings.font, options: options)
        view.autoresizingMask = [.width, .height]
        view.processDelegate = self
        terminalHost.addSubview(view)
        terminalView = view

        needsFreshSession = false
        view.repairTabStopsIfNeeded()
        applyAppearance()
        startShell()
    }

    private func recreateTerminalView() {
        if let old = terminalView {
            old.processDelegate = nil
            old.terminate()
            old.removeFromSuperview()
        }
        terminalView = nil
        sessionAlive = false
        needsFreshSession = false
        createTerminalView()
    }

    private func startShell() {
        guard let terminalView else { return }
        let launch = settings.shellLaunch

        switch launch {
        case let .program(program):
            terminalView.startProcess(
                executable: program,
                args: [],
                environment: ShellEnvironment.make(shell: program),
                execName: Self.loginName(for: program),
                currentDirectory: NSHomeDirectory()
            )

        case let .command(shell, line):
            // Only a shell can interpret a command line, so the account's own
            // login shell parses it and then `exec`s what it found.
            terminalView.startProcess(
                executable: shell,
                args: ["-c", line],
                environment: ShellEnvironment.make(shell: shell),
                execName: Self.loginName(for: shell),
                currentDirectory: NSHomeDirectory()
            )
        }
        sessionAlive = true
    }

    private static func loginName(for program: String) -> String {
        "-" + (program as NSString).lastPathComponent
    }

    // MARK: - Appearance

    private func applyAppearance() {
        let theme = settings.theme
        let glass = settings.usesGlass

        updateGlass()

        container.backgroundColor = glass ? .clear : theme.nsBackground
        panel.backgroundColor = .clear
        panel.invalidateShadow()

        guard let terminalView else { return }
        terminalView.font = settings.font
        terminalView.nativeBackgroundColor = theme.nsBackground
        terminalView.nativeForegroundColor = theme.nsForeground
        terminalView.caretColor = theme.nsCursor
        terminalView.installColors(theme.terminalPalette)

        // Over glass the theme is painted at partial opacity so the material
        // (and the desktop behind it) shows through. SwiftTerm keeps its backing
        // layer clear in that case, and `translucentCellBackgrounds` stops ANSI
        // backgrounds from punching opaque holes in the glass.
        terminalView.translucentCellBackgrounds = glass
        terminalView.backgroundOpacity = glass ? settings.glassTint : 1
        terminalView.layer?.backgroundColor = glass
            ? NSColor.clear.cgColor
            : theme.nsBackground.cgColor
    }

    /// Puts the terminal's host view inside `parent`, filling it.
    private func attachTerminalHost(to parent: NSView) {
        if terminalHost.superview !== parent {
            terminalHost.removeFromSuperview()
        }
        terminalHost.autoresizingMask = [.width, .height]
        terminalHost.frame = parent.bounds
        parent.addSubview(terminalHost)
    }

    /// Adds or removes the `NSGlassEffectView` that sits under the terminal.
    ///
    /// The panel is already non-opaque with a clear background, which is the
    /// part only AppKit can do: it lets the material sample the desktop and the
    /// windows behind the panel instead of the terminal's own window.
    private func updateGlass() {
        guard #available(macOS 26.0, *) else { return }

        guard settings.usesGlass else {
            guard let glass = glassView else { return }
            (glass as? NSGlassEffectView)?.contentView = nil
            glass.removeFromSuperview()
            glassView = nil
            attachTerminalHost(to: container)
            return
        }

        let glass: NSGlassEffectView
        if let existing = glassView as? NSGlassEffectView {
            glass = existing
        } else {
            glass = NSGlassEffectView()
            glass.style = .regular
            // The container already clips the bottom corners; a second, larger
            // radius here would leave a gap along the top edge.
            glass.cornerRadius = 0
            glass.autoresizingMask = [.width, .height]
            glass.frame = container.bounds
            container.addSubview(glass)
            glassView = glass
        }

        // A hint of the theme in the material itself, so the glass reads as
        // Guac-colored rather than as the desktop's own colors.
        glass.tintColor = settings.theme.nsBackground.withAlphaComponent(0.35)

        // The material composites above any *sibling* view, so the terminal has
        // to live inside the glass effect's documented `contentView`; ordering
        // subviews around it does not work (NSGlassEffectView.h says so).
        if terminalHost.superview !== glass {
            glass.contentView = nil
            attachTerminalHost(to: glass)
            glass.contentView = terminalHost
        }
        glass.frame = container.bounds
        terminalHost.frame = glass.bounds
    }
}

// MARK: - LocalProcessTerminalViewDelegate

extension TerminalController: LocalProcessTerminalViewDelegate {
    func sizeChanged(source _: LocalProcessTerminalView, newCols _: Int, newRows _: Int) {
        // SwiftTerm drives the PTY window size itself; nothing to do.
    }

    func setTerminalTitle(source _: LocalProcessTerminalView, title _: String) {
        // A drop-down terminal has no title bar to show it in.
    }

    func hostCurrentDirectoryUpdate(source _: TerminalView, directory _: String?) {
        // Kept for future use; the app does not track the working directory.
    }

    func processTerminated(source: TerminalView, exitCode _: Int32?) {
        // `exit` was typed, or the program the panel ran — a multiplexer, say —
        // finished. Either way there is nothing left to look at, so the panel
        // drops away exactly as if the shortcut had been pressed, and the next
        // show starts a fresh session.
        guard let view = source as? GuacTerminalView, view === terminalView else { return }
        sessionAlive = false
        hide()
    }

    func processFailedToStart(source: TerminalView, error: LocalProcessError) {
        // The exec itself failed — a mistyped path, or a program that has been
        // uninstalled. Nothing is running, so the panel has nothing to show.
        guard let view = source as? GuacTerminalView, view === terminalView else { return }
        NSLog("[GuacTerm] could not start the session: \(error)")
        sessionAlive = false
        hide()
    }
}
