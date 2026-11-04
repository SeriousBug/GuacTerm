import AppKit
import SwiftTerm

/// The terminal view GuacTerm actually uses.
///
/// It exists for three reasons:
///
/// - GPU rendering can only be switched on once the view has a window, and the
///   Core Graphics renderer is a perfectly good fallback, so the attempt
///   belongs here where it can fail quietly instead of at construction time.
/// - A click on the panel while another app is frontmost should reach the
///   terminal, not just activate the window.
/// - Right-clicking should offer the usual Copy/Paste when the program in the
///   terminal has not asked for the mouse itself.
final class GuacTerminalView: LocalProcessTerminalView {
    private var didAttemptMetal = false

    override init(frame: CGRect, font: NSFont? = nil, options: TerminalOptions) {
        super.init(frame: frame, font: font, options: options)
        installContextMenu()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        enableMetalIfPossible()
    }

    /// GuacTerm's panel is often clicked straight from another app; without
    /// this the first click would be spent activating the window.
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    private func enableMetalIfPossible() {
        guard !didAttemptMetal, window != nil else { return }
        didAttemptMetal = true

        // Escape hatch for diagnosing renderer problems on a specific machine.
        if ProcessInfo.processInfo.environment["GUACTERM_CPU_RENDER"] == "1" {
            NSLog("[GuacTerm] Metal renderer disabled by GUACTERM_CPU_RENDER")
            return
        }

        do {
            try setUseMetal(true)
            NSLog("[GuacTerm] using the Metal renderer")
        } catch {
            // Older hardware, a software renderer, or a machine without a
            // usable Metal device: keep drawing with Core Graphics.
            NSLog("[GuacTerm] Metal unavailable, using Core Graphics: \(error)")
        }
    }

    /// The narrowest grid that still needs ``repairTabStopsIfNeeded()``: the
    /// 80-column default's last tab stop is column 72, and a grid that narrow
    /// ends before the gap past it.
    static let narrowestGridNeedingTabRepair = 74

    /// Gives the grid the tab stops of its own width.
    ///
    /// SwiftTerm builds its buffers for its 80-column default before the view's
    /// size reaches them, and growing a buffer adds empty slots to the tab-stop
    /// table without filling them in. Only a resize re-runs the tab-stop setup,
    /// so the grid otherwise keeps the stops of an 80-column terminal (columns
    /// 0 to 72) and a TAB past column 72 goes to the *last column of the row*
    /// instead of to the next stop. `ls` pads its columns with tabs, so each
    /// padded run jumped to the right edge and the rest of the word wrapped onto
    /// the next line.
    ///
    /// Narrowing the view and restoring it is the cheapest way to ask for that
    /// setup. Run it before the shell starts: the screen is empty and there is
    /// no PTY yet, so the two reflows cost nothing and nothing the shell prints
    /// can be disturbed. The grid ends up the size it started.
    func repairTabStopsIfNeeded() {
        let size = frame.size
        guard let intermediate = Self.tabStopRepairSize(for: size, cols: terminalDimensions.cols) else {
            return
        }
        setFrameSize(intermediate)
        setFrameSize(size)
    }

    /// The size to narrow a `size` view to before restoring it, or `nil` when
    /// its grid does not need repairing. Split out from the resize itself so the
    /// decision can be tested without a view.
    static func tabStopRepairSize(for size: NSSize, cols: Int) -> NSSize? {
        guard cols >= narrowestGridNeedingTabRepair, size.width > 1, size.height > 1 else {
            return nil
        }
        return NSSize(width: size.width / 2, height: size.height)
    }

    /// Nil targets send the action down the responder chain, which lands on
    /// this view's `copy(_:)`, `paste(_:)` and `selectAll(_:)`.
    private func installContextMenu() {
        let menu = NSMenu()

        let copy = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "")
        copy.target = nil
        menu.addItem(copy)

        let paste = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "")
        paste.target = nil
        menu.addItem(paste)

        menu.addItem(.separator())

        let selectAll = NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "")
        selectAll.target = nil
        menu.addItem(selectAll)

        self.menu = menu
    }
}
