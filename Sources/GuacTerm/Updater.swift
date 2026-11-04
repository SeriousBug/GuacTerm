import AppKit
import Sparkle

/// Sparkle, wrapped in the small part of it GuacTerm uses.
///
/// The feed is the `appcast.xml` asset of the newest GitHub release (see
/// `SUFeedURL` in project.yml), so a check always reads whatever is published
/// last and nothing has to be hosted anywhere else. The appcast and every
/// archive in it have to carry a signature from the key whose public half is
/// `SUPublicEDKey`; the private half sits in the login Keychain under the
/// `guacterm` account and is only ever read by `scripts/appcast.sh`.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    /// False for a bundle that has no feed to read, which is what a build
    /// assembled by hand looks like. Settings then says nothing about updates
    /// rather than offering a check that can only fail.
    let isAvailable: Bool

    /// Sparkle keeps this in the app's own defaults (`SUEnableAutomaticChecks`
    /// is only the first-run default), so it is mirrored here for the toggle
    /// and not stored in ``Settings``.
    @Published private(set) var automaticallyChecksForUpdates: Bool

    private let controller: SPUStandardUpdaterController?

    private init() {
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        let configured = !(feed ?? "").isEmpty && !(key ?? "").isEmpty

        if configured {
            let controller = SPUStandardUpdaterController(
                startingUpdater: false,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            // Started by hand so a failure is reported once, here, instead of
            // being buried in Sparkle's own logging.
            do {
                try controller.updater.start()
            } catch {
                NSLog("[GuacTerm] could not start the updater: \(error.localizedDescription)")
            }
            self.controller = controller
            automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        } else {
            controller = nil
            automaticallyChecksForUpdates = false
        }

        isAvailable = configured
    }

    /// Checks now, unless a check is already running: Sparkle refuses to start
    /// a second one, and the menu item stays clickable either way.
    func checkForUpdates() {
        guard let controller, controller.updater.canCheckForUpdates else { return }
        controller.checkForUpdates(nil)
    }

    /// Written through to Sparkle, then read back, because Sparkle decides what
    /// the setting actually is.
    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
        automaticallyChecksForUpdates = controller?.updater.automaticallyChecksForUpdates ?? false
    }
}
