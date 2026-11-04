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

    var isShown: Bool { visible }

    init(settings: Settings) {
        self.settings = settings
        self.panel = DropDownPanel(
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
    /// for that behaviour in Settings.
    func handleApplicationDeactivated() {
        guard settings.hideOnFocusLoss, visible else { return }
        if let shownAt, Date().timeIntervalSince(shownAt) < Timing.deactivationGrace { return }
        hide()
    }

    func shutdown() {
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
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
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
        let shell = settings.resolvedShellPath
        // A leading dash makes the shell a login shell, so it reads the same
        // startup files it would in Terminal.app.
        let loginName = "-" + (shell as NSString).lastPathComponent

        terminalView.startProcess(
            executable: shell,
            args: [],
            environment: ShellEnvironment.make(shell: shell),
            execName: loginName,
            currentDirectory: NSHomeDirectory()
        )
        sessionAlive = true
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

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // SwiftTerm drives the PTY window size itself; nothing to do.
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        // A drop-down terminal has no title bar to show it in.
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        // Kept for future use; the app does not track the working directory.
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        // The shell exited (or `exit` was typed). A fresh one starts the next
        // time the panel drops down.
        sessionAlive = false
    }
}
