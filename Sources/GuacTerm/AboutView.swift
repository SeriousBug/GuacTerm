import AppKit
import SwiftUI

/// The About window: what the app is, the MIT license it is released under, and
/// the notices of the third-party work it bundles or links.
///
/// The two license areas are separate scrollers rather than one long page, so
/// GuacTerm's own license stays in view while a third-party notice is read.
struct AboutView: View {
    /// The component whose notice the detail pane shows.
    @State private var selectedComponentID = AboutContent.components[0].id

    private let padding: CGFloat = 22

    /// Most of the MIT text without scrolling at the window's default size. It
    /// scrolls for the rest, and for a window that was made smaller.
    private let licensePaneHeight: CGFloat = 220

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Divider()
            licenseSection
            Divider()
            thirdPartySection
        }
        .padding(padding)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(AppInfo.name)
                    .font(.largeTitle.weight(.semibold))
                Text(AppInfo.tagline)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(AppInfo.versionDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - GuacTerm's license

    private var licenseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("License")
                    .font(.headline)
                badge(AboutContent.licenseName)
                Spacer(minLength: 12)
                Text(AboutContent.copyrightLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Text(AboutContent.licenseSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            licenseText(AboutContent.licenseText)
                .frame(height: licensePaneHeight)
        }
    }

    // MARK: - Third-party notices

    private var thirdPartySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Third-Party Licenses")
                    .font(.headline)
                Spacer(minLength: 12)
                Text("\(AboutContent.components.count) components")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(AboutContent.thirdPartySummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Component", selection: $selectedComponentID) {
                ForEach(AboutContent.components) { component in
                    Text(component.name).tag(component.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            componentDetail
                .frame(maxHeight: .infinity)
        }
    }

    private var componentDetail: some View {
        let component = selectedComponent
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                badge(component.licenseName)
                Text(component.usage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                upstreamLink(component)
            }

            Text(component.copyright)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if let notice = component.notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            licenseText(component.licenseText)
                .frame(minHeight: 80, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Pieces

    /// The license itself, as selectable text in a box that reads like a
    /// document rather than like chrome.
    private func licenseText(_ text: String) -> some View {
        ScrollView(.vertical) {
            Text(text)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor))
        )
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(.quaternary))
    }

    @ViewBuilder
    private func upstreamLink(_ component: AboutContent.Component) -> some View {
        if let url = URL(string: component.upstream) {
            Link(destination: url) {
                HStack(spacing: 3) {
                    Text("Upstream")
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                }
                .font(.caption)
            }
            .help(component.upstream)
        }
    }

    private var appIcon: NSImage {
        NSApp.applicationIconImage
            ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }

    private var selectedComponent: AboutContent.Component {
        AboutContent.components.first { $0.id == selectedComponentID }
            ?? AboutContent.components[0]
    }
}
