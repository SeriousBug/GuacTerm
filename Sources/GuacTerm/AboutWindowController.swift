import AppKit
import SwiftUI

/// Hosts ``AboutView`` in a window of its own. GuacTerm is an accessory app, so
/// this and the settings window are the only conventional windows it shows.
@MainActor
final class AboutWindowController: NSWindowController {
    init() {
        let hosting = NSHostingController(rootView: AboutView())
        hosting.sizingOptions = []

        let window = NSWindow(contentViewController: hosting)
        window.title = "About \(AppInfo.name)"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.moveToActiveSpace)

        // Big enough that a whole license is readable without the page's own
        // scrolling being in the way. The height is kept within the screen it
        // opens on, so a short display gets a smaller window rather than one
        // whose top is under the menu bar.
        let visible = NSScreen.underMouse.visibleFrame
        let size = NSSize(
            width: max(560, min(680, visible.width - 60)),
            height: max(700, min(800, visible.height - 60))
        )
        window.setContentSize(size)
        window.contentMinSize = NSSize(width: 560, height: 700)
        window.setFrameOrigin(
            NSPoint(
                x: visible.midX - window.frame.width / 2,
                y: visible.midY - window.frame.height / 2
            )
        )

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate()
    }
}
