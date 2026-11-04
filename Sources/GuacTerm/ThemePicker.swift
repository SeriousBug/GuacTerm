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
//  It is also where themes are imported: any `.itermcolors` file can be dropped
//  on the sheet or picked with the Import button, which copies it into the
//  user's library (see ThemeLibrary) and selects it. Imported schemes are listed
//  above the bundled ones, because they are the ones that just arrived.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A searchable, live-applying list of every ``TerminalTheme`` the user has.
struct ThemePicker: View {
    @ObservedObject var library: ThemeLibrary

    /// The selection being edited: there is one of these sheets per scheme.
    let slot: ThemeSlot

    /// The identifier the sheet reads and writes, so browsing recolors the
    /// terminal behind it as it goes.
    @Binding var themeID: String

    @Environment(\.dismiss) private var dismiss

    /// The theme that was in effect when the sheet opened, which Cancel
    /// restores. Stored rather than derived so a browse-then-cancel round trip
    /// leaves no trace in UserDefaults.
    private let originalThemeID: String

    @State private var query = ""
    @State private var hoveredThemeID: String?

    /// What the last import did, shown in the footer. Sticky rather than a
    /// transient toast: a failed file has to stay readable while the user goes
    /// to look at it.
    @State private var notice: ThemeLibrary.ImportSummary?

    /// True while `.itermcolors` files are being dragged over the sheet.
    @State private var isDropTarget = false

    private static let width: CGFloat = 560
    private static let height: CGFloat = 580

    init(library: ThemeLibrary, slot: ThemeSlot, themeID: Binding<String>) {
        self.library = library
        self.slot = slot
        _themeID = themeID
        originalThemeID = themeID.wrappedValue
    }

    /// The scheme the sheet is showing a sample of.
    private var theme: TerminalTheme {
        library.theme(id: themeID, fallback: slot.defaultThemeID)
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
        .dropDestination(for: URL.self) { urls, _ in
            apply(urls)
            return true
        } isTargeted: { targeted in
            isDropTarget = targeted
        }
        .overlay {
            if isDropTarget {
                dropTargetOverlay
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Text(slot.label)
                    .font(.title2.weight(.semibold))
                Spacer()
                Text(countDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button {
                    importWithOpenPanel()
                } label: {
                    Label("Import…", systemImage: "square.and.arrow.down")
                }
                .controlSize(.small)
                .help("Import an iTerm2 colour scheme (.itermcolors)")
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
                "Search \(library.all.count) themes",
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
        let total = library.all.count
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
                        if !importedMatches.isEmpty {
                            sectionHeader("Imported", detail: "right-click to manage")
                            ForEach(importedMatches) { theme in
                                row(theme)
                            }
                        }
                        if !bundledMatches.isEmpty {
                            if !importedMatches.isEmpty {
                                sectionHeader("Bundled", detail: nil)
                            }
                            ForEach(bundledMatches) { theme in
                                row(theme)
                            }
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
                proxy.scrollTo(themeID, anchor: .center)
            }
        }
    }

    private func sectionHeader(_ title: String, detail: String?) -> some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    /// An imported scheme gets a context menu; a bundled one has nothing to
    /// manage, and an empty menu is worse than none.
    @ViewBuilder
    private func row(_ theme: TerminalTheme) -> some View {
        if library.isImported(theme) {
            rowBody(theme)
                .contextMenu {
                    Button("Show in Finder") {
                        library.reveal(theme)
                    }
                    Button("Remove Theme") {
                        remove(theme)
                    }
                }
        } else {
            rowBody(theme)
        }
    }

    private func rowBody(_ theme: TerminalTheme) -> some View {
        let isCurrent = theme.id == themeID
        let isHovered = theme.id == hoveredThemeID

        return Button {
            themeID = theme.id
        } label: {
            HStack(spacing: 10) {
                ThemeChip(theme: theme)

                Text(theme.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)

                if library.isImported(theme) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .help("Imported from \(library.fileURL(for: theme)?.lastPathComponent ?? "a file")")
                }

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
        if isCurrent {
            return Color.accentColor.opacity(0.16)
        }
        if isHovered {
            return Color.primary.opacity(0.07)
        }
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

    /// Shown while files are dragged over the sheet, so the drop does not have
    /// to be taken on faith.
    private var dropTargetOverlay: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(
                Color.accentColor,
                style: StrokeStyle(lineWidth: 2, dash: [6, 4])
            )
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.08))
            )
            .overlay {
                Label("Drop to import", systemImage: "square.and.arrow.down")
                    .font(.callout.weight(.medium))
            }
            .padding(8)
            .allowsHitTesting(false)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemeSample(theme: theme)

            noticeLine

            HStack(spacing: 10) {
                Text(theme.name)
                    .font(.callout.weight(.medium))
                if theme.isLight {
                    Text("Light")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if library.isImported(theme) {
                    Text("Imported")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if library.isImported(theme) {
                    Button("Remove") {
                        remove(theme)
                    }
                    .help("Move the scheme's file from ~/Library/Application Support/GuacTerm/Themes to the Trash")
                }
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

    /// What the last import did, or how to do one. Keeping the hint here is how
    /// the drop target is discoverable without a toolbar or a help window.
    @ViewBuilder
    private var noticeLine: some View {
        if let notice, !notice.isEmpty {
            let failed = !notice.failures.isEmpty
            Label(notice.message, systemImage: failed ? "exclamationmark.triangle.fill" : "checkmark.circle")
                .font(.caption)
                .foregroundStyle(failed ? Color.orange : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Drop .\(ITermColors.pathExtension) files here to import a theme.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Data

    /// Every scheme whose name or identifier contains all the words typed, so
    /// "nord light" narrows instead of widening the result.
    private var matches: [TerminalTheme] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return library.all }

        let words = needle.split(separator: " ").map(String.init)
        return library.all.filter { theme in
            let haystack = "\(theme.name) \(theme.id)".lowercased()
            return words.allSatisfy(haystack.contains)
        }
    }

    private var importedMatches: [TerminalTheme] {
        matches.filter(library.isImported)
    }

    private var bundledMatches: [TerminalTheme] {
        matches.filter { !library.isImported($0) }
    }

    // MARK: - Actions

    /// Enter picks the first match, which makes "type, Enter" the fast path.
    private func selectFirstMatch() {
        guard let first = matches.first else { return }
        themeID = first.id
    }

    private func cancel() {
        if themeID != originalThemeID {
            themeID = originalThemeID
        }
        dismiss()
    }

    private func importWithOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "Import iTerm2 Theme"
        panel.prompt = "Import"
        panel.message = "Choose one or more .\(ITermColors.pathExtension) files."
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        // The declared type, or a dynamic type carrying the same extension tag:
        // either way the panel filters on `.itermcolors` rather than on every
        // file on disk.
        panel.allowedContentTypes = [
            UTType(filenameExtension: ITermColors.pathExtension) ?? .data,
        ]

        guard panel.runModal() == .OK else { return }
        apply(panel.urls)
    }

    /// Imports the files and shows what happened, selecting the first scheme
    /// that made it in so the import is visible without hunting for it.
    private func apply(_ urls: [URL]) {
        let summary = library.importThemes(from: urls)
        if summary.isEmpty {
            return
        }
        notice = summary
        if let id = summary.firstImportedID {
            themeID = id
        }
    }

    private func remove(_ theme: TerminalTheme) {
        guard library.remove(theme) else { return }
        notice = nil
        if themeID == theme.id {
            themeID = slot.defaultThemeID
        }
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
                ForEach(0 ..< 16, id: \.self) { index in
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
