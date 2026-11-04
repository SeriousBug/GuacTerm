import AppKit
import SwiftUI

/// The About window: what the app is, the MIT license it is released under, and
/// the notices of the third-party work it is built on.
///
/// The license texts are boxes of their own rather than one wall of text, so
/// GuacTerm's license and each project's notice stay recognisably separate. The
/// page is what scrolls: a box inside a scrolling page that scrolled by itself
/// would be one scroll too many.
struct AboutView: View {
    private let padding: CGFloat = 22

    // MARK: - Body

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 22) {
                header
                licenseSection
                thirdPartySection
            }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
                sourceLink(AboutContent.sourceCode)
            }

            licenseText(AboutContent.licenseText)
        }
    }

    // MARK: - Third-party notices

    private var thirdPartySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Third-Party Licenses")
                .font(.headline)

            Text(AboutContent.thirdPartySummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 16) {
                ForEach(AboutContent.components) { component in
                    componentBlock(component)
                }
            }
        }
    }

    /// One project: who it is and whose copyright it carries, then the license
    /// itself.
    private func componentBlock(_ component: AboutContent.Component) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(component.name)
                    .font(.callout.weight(.semibold))
                badge(component.licenseName)
                Spacer(minLength: 12)
                Text(component.copyright)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                sourceLink(component.upstream)
            }

            if let notice = component.notice {
                noticeText(notice)
            }

            licenseText(component.licenseText)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Pieces

    /// A note about a component, as Markdown so the file it points at — the
    /// scheme credits, say — can be a link right where it is named.
    ///
    /// The colors are set on the text itself rather than with `foregroundStyle`,
    /// which would paint over the accent color and leave a link that reads as
    /// one more sentence.
    private func noticeText(_ markdown: String) -> some View {
        var text = (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
        text.foregroundColor = .secondary

        for range in text.runs.filter({ $0.link != nil }).map(\.range) {
            text[range].foregroundColor = .accentColor
            text[range].underlineStyle = .single
        }

        return Text(text)
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    /// The license itself, as selectable text in a box that reads like a
    /// document rather than like chrome.
    private func licenseText(_ text: String) -> some View {
        Text(text)
            .font(.caption.monospaced())
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
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

    /// A pointer at the project itself, for GuacTerm and for the work it is
    /// built on alike.
    @ViewBuilder
    private func sourceLink(_ urlString: String) -> some View {
        if let url = URL(string: urlString) {
            Link(destination: url) {
                HStack(spacing: 3) {
                    Text("Source code")
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                }
                .font(.caption)
            }
            .help(urlString)
        }
    }

    private var appIcon: NSImage {
        NSApp.applicationIconImage
            ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }
}
