import AppKit

// GuacTerm is a menu-bar (LSUIElement) app: no Dock icon, no document model.
// The whole app is one drop-down window plus a settings window.
let application = NSApplication.shared
let delegate = AppDelegate()

application.setActivationPolicy(.accessory)
application.delegate = delegate

withExtendedLifetime(delegate) {
    application.run()
}
