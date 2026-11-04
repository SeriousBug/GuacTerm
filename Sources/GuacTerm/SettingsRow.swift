import SwiftUI

/// One setting: a label on the left, its control right-aligned, and an optional
/// caption underneath saying what the setting does.
///
/// Shared so every group of rows is laid out the same way, wherever it lives.
struct SettingsRow<Control: View>: View {
    let title: String
    var caption: String?
    let control: Control

    init(title: String, caption: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.caption = caption
        self.control = control()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 16) {
                Text(title)
                    .fixedSize()
                Spacer(minLength: 12)
                control
            }
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
