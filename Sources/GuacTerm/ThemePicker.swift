//
//  ThemePicker.swift
//  GuacTerm
//
//  The theme chooser, shown as a sheet from Settings.
//
//  The catalog holds ~890 schemes, which is far too many for a pop-up menu, so
//  the sheet offers a search field, a lazily built list with a color chip per
//  row, and a live sample of the highlighted scheme. Selection applies
//  immediately — the terminal behind the sheet recolors as you browse — and
//  Cancel puts the original theme back.
//

import SwiftUI

/// A searchable, live-applying list of every ``TerminalTheme`` in the catalog.
struct ThemePicker: View {

    @ObservedObject var settings: Settings

    @Environment(\.dismiss) private var dismiss

    /// The theme that was in effect when the sheet opened, which Cancel
    /// restores. Stored rather than derived so a browse-then-cancel round trip
    /// leaves no trace in UserDefaults.
    private let originalThemeID: String

    @State private var query = ""
    @State private var hoveredThemeID: String?

    private static let width: CGFloat = 560
    private static let height: CGFloat = 580

    init(settings: Settings) {
        self.settings = settings
        self.originalThemeID = settings.themeID
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: Self.width, height: Self.height)
        .onExitCommand(perform: cancel)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Themes")
                    .font(.title2.weight(.semibold))
                Spacer()
                Text(countDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            searchField
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(
                "Search \(TerminalTheme.catalog.count) themes",
                text: $query
            )
            .textFieldStyle(.plain)
            .onSubmit(selectFirstMatch)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear the search")
            }
        }
        .font(.body)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var countDescription: String {
        let shown = matches.count
        let total = TerminalTheme.catalog.count
        return shown == total ? "\(total) themes" : "\(shown) of \(total)"
    }

    // MARK: - List

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if matches.isEmpty {
                        emptyState
                    } else {
                        ForEach(matches) { theme in
                            row(theme)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .task {
                // LazyVStack only builds the rows around the viewport, so the
                // current theme has to be asked for after the first layout pass.
                try? await Task.sleep(for: .milliseconds(60))
                proxy.scrollTo(settings.themeID, anchor: .center)
            }
        }
    }

    private func row(_ theme: TerminalTheme) -> some View {
        let isCurrent = theme.id == settings.themeID
        let isHovered = theme.id == hoveredThemeID

        return Button {
            settings.themeID = theme.id
        } label: {
            HStack(spacing: 10) {
                ThemeChip(theme: theme)

                Text(theme.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)

                Spacer(minLength: 8)

                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(background(isCurrent: isCurrent, isHovered: isHovered))
            )
        }
        .buttonStyle(.plain)
        .id(theme.id)
        .onHover { hovering in
            if hovering {
                hoveredThemeID = theme.id
            } else if hoveredThemeID == theme.id {
                hoveredThemeID = nil
            }
        }
    }

    private func background(isCurrent: Bool, isHovered: Bool) -> Color {
        if isCurrent { return Color.accentColor.opacity(0.16) }
        if isHovered { return Color.primary.opacity(0.07) }
        return Color.clear
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No theme matches “\(query)”")
                .font(.callout.weight(.medium))
            Text("Try a shorter search, or the scheme's identifier such as “nord”.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemeSample(theme: settings.theme)

            HStack(spacing: 10) {
                Text(settings.theme.name)
                    .font(.callout.weight(.medium))
                if settings.theme.isLight {
                    Text("Light")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 20)
    }

    // MARK: - Data

    /// Every scheme whose name or identifier contains all the words typed, so
    /// "nord light" narrows instead of widening the result.
    private var matches: [TerminalTheme] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return TerminalTheme.catalog }

        let words = needle.split(separator: " ").map(String.init)
        return TerminalTheme.catalog.filter { theme in
            let haystack = "\(theme.name) \(theme.id)".lowercased()
            return words.allSatisfy(haystack.contains)
        }
    }

    // MARK: - Actions

    /// Enter picks the first match, which makes "type, Enter" the fast path.
    private func selectFirstMatch() {
        guard let first = matches.first else { return }
        settings.themeID = first.id
    }

    private func cancel() {
        if settings.themeID != originalThemeID {
            settings.themeID = originalThemeID
        }
        dismiss()
    }
}

// MARK: - Chip

/// A miniature of the scheme: the background with a few accent colors on it.
private struct ThemeChip: View {

    let theme: TerminalTheme

    /// ANSI 1-6, the colors a listing or a diff actually uses.
    private static let indices = [1, 2, 3, 4, 5, 6]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Color(nsColor: theme.nsAnsi[index]))
                    .frame(width: 5, height: 11)
            }
        }
        .padding(.horizontal, 4)
        .frame(width: 52, height: 20)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(nsColor: theme.nsBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color(nsColor: theme.nsForeground).opacity(0.28), lineWidth: 1)
        )
    }
}

// MARK: - Sample

/// A full-width preview of the scheme being considered: the whole palette, then
/// a prompt line with the cursor block, drawn on the scheme's own background.
private struct ThemeSample: View {

    let theme: TerminalTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 2) {
                ForEach(0..<16, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color(nsColor: theme.nsAnsi[index]))
                        .frame(height: 10)
                }
            }

            HStack(spacing: 5) {
                Text("~/code/guacterm")
                    .foregroundStyle(Color(nsColor: theme.nsAnsi[2]))
                Text("❯")
                    .foregroundStyle(Color(nsColor: theme.nsAnsi[8]))
                Text("make run")
                    .foregroundStyle(Color(nsColor: theme.nsForeground))
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Color(nsColor: theme.nsCursor))
                    .frame(width: 6, height: 13)
                Spacer(minLength: 0)
            }
            .font(.system(size: 11.5, design: .monospaced))
            .lineLimit(1)
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: theme.nsBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: theme.nsForeground).opacity(0.18), lineWidth: 1)
        )
    }
}
