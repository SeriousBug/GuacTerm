import AppKit
import SwiftUI

/// Hosts the SwiftUI settings pane in a regular window. GuacTerm is an
/// accessory app, so this is the only conventional window it ever shows.
@MainActor
final class SettingsWindowController: NSWindowController {

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
        window.center()

        super.init(window: window)
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
}
