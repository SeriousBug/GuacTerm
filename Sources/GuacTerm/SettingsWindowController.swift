import AppKit
import SwiftUI

/// Hosts the SwiftUI settings pane in a regular window. GuacTerm is an
/// accessory app, so this is the only conventional window it ever shows.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    /// Called when the window closes, so the terminal can stop treating itself
    /// as a preview and go back to obeying the focus settings.
    var onClose: (() -> Void)?

    private var hasBeenPlaced = false

    /// - Parameter showsThemePickerOnAppear: open the theme sheet immediately,
    ///   which is what the `--theme-picker` launch flag asks for.
    init(settings: Settings, showsThemePickerOnAppear: Bool = false) {
        let hosting = NSHostingController(
            rootView: SettingsView(
                settings: settings,
                showsThemePickerOnAppear: showsThemePickerOnAppear
            )
        )
        hosting.sizingOptions = []

        let window = NSWindow(contentViewController: hosting)
        window.title = "\(AppInfo.name) Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 560, height: 660))
        window.contentMinSize = NSSize(width: 560, height: 480)
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.moveToActiveSpace)
        // Open on the display the terminal drops down on. `center()` picks a
        // screen of its own on a multi-display setup, which would leave the
        // pane and the preview it is driving on two different monitors.
        let screen = NSScreen.underMouse
        let size = window.frame.size
        let visible = screen.visibleFrame
        window.setFrameOrigin(
            NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2
            )
        )

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate()
    }

    /// Centers the window in the part of the screen the terminal leaves free, so
    /// the preview above it stays visible. Falls back to the middle of the
    /// screen when the panel leaves too little room.
    ///
    /// Only done the first time: after that the window is wherever the user put
    /// it.
    func place(clearOf panelFrame: NSRect?) {
        guard let window, !hasBeenPlaced else { return }
        hasBeenPlaced = true

        let visible = NSScreen.underMouse.visibleFrame
        let size = window.frame.size

        if let panelFrame {
            let free = NSRect(
                x: visible.minX,
                y: visible.minY,
                width: visible.width,
                height: panelFrame.minY - visible.minY
            )
            if free.height >= size.height + 24 {
                window.setFrameOrigin(
                    NSPoint(x: free.midX - size.width / 2, y: free.midY - size.height / 2)
                )
                return
            }
        }

        window.setFrameOrigin(
            NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        )
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

extension NSScreen {

    /// The screen the pointer is on, which is where GuacTerm puts its windows:
    /// the panel drops down there, so the settings window opens there too.
    @MainActor
    static var underMouse: NSScreen {
        let mouse = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? main
            ?? screens[0]
    }
}
