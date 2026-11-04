import SwiftUI

/// The update rows of the settings pane.
///
/// Sparkle's own windows do the downloading and installing; all this does is
/// hand it over and show where the updates come from.
struct UpdatesSettings: View {
    @ObservedObject var updater: Updater

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(
                title: "Automatic Updates",
                caption: "Check once a day in the background, and offer the new version when there is one."
            ) {
                Toggle("Automatic Updates", isOn: automaticallyChecksUpdatesBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            Divider()
            SettingsRow(
                title: "Software Update",
                caption: """
                Updates come from this app's GitHub releases, and only an update \
                signed with this app's key is installed.
                """
            ) {
                Button("Check Now…") {
                    updater.checkForUpdates()
                }
            }
        }
    }

    /// Sparkle is the one that stores the setting, so the toggle writes through
    /// ``Updater`` rather than into ``Settings``.
    private var automaticallyChecksUpdatesBinding: Binding<Bool> {
        Binding(
            get: { updater.automaticallyChecksForUpdates },
            set: { updater.setAutomaticallyChecksForUpdates($0) }
        )
    }
}
