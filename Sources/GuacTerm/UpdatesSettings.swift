import SwiftUI

/// The update rows of the settings pane.
///
/// Sparkle's own windows do the downloading and installing; all this does is
/// hand it over and let the user ask for a check.
struct UpdatesSettings: View {
    @ObservedObject var updater: Updater

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(title: "Automatic Updates") {
                Toggle("Automatic Updates", isOn: automaticallyChecksUpdatesBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            HStack(spacing: 16) {
                Spacer(minLength: 12)
                Button("Check Now") {
                    updater.checkForUpdates()
                }
            }
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
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
