//
//  ThemeLibrary.swift
//  GuacTerm
//
//  Everything about the themes the user brings with them.
//
//  GuacTerm ships ~890 schemes, and that is still not "any theme": people have
//  their own `.itermcolors` files, from iTerm2's colour presets, from the
//  upstream collection's newest additions, from a gist. So the catalog is only
//  the starting point — an imported file is kept as the user's own document, in
//
//      ~/Library/Application Support/GuacTerm/Themes/*.itermcolors
//
//  rather than being converted and forgotten. Storing the original keeps the
//  scheme readable and re-importable, makes "remove" mean deleting a file the
//  user can see in the Finder, and means a badly converted scheme can be fixed
//  by editing the file instead of by uninstalling anything.
//

import AppKit

/// The bundled catalog plus the schemes the user imported, in one list.
///
/// `@MainActor` because it is the model behind SwiftUI views and because the
/// terminal repaints off ``onChange``; parsing itself is cheap (a few KB of
/// property list per file) so it happens right here rather than on a background
/// queue that would only add ordering problems.
@MainActor
final class ThemeLibrary: ObservableObject {
    static let shared = ThemeLibrary()

    /// Where imported schemes live. Not sandboxed, so this is the real user
    /// library rather than a container, which is what makes the files easy to
    /// find, edit and back up.
    static var directory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent(AppInfo.name, isDirectory: true)
            .appendingPathComponent("Themes", isDirectory: true)
    }

    /// Identifier prefix for imported themes.
    ///
    /// The identifier ends up in `UserDefaults`, so it has to stay stable for a
    /// given file and must never collide with a vendored scheme. Prefixing is
    /// cheaper and clearer than trying to re-use the bundled ids: the picker can
    /// then tell the two apart without consulting anything, and a scheme that is
    /// both bundled and imported keeps working as two entries instead of one
    /// shadowing the other.
    static let importedIDPrefix = "imported-"

    /// The identifier an imported scheme gets, from the name its file gives it:
    /// `"Solarized Dark.itermcolors"` -> `"imported-solarized-dark-1m1k"`.
    ///
    /// The four characters at the end are a digest of the name, and they are
    /// what keeps two schemes apart whose names differ but whose slugs do not
    /// (`"Nord"` and `"Nord!"` both wanted `imported-nord`), and what a name
    /// with no ASCII letters left over from the slug — `"日本語"` — is left
    /// with. Hashing the name rather than the file keeps the identifier the
    /// same across launches, which is what `UserDefaults` is pointing at.
    static func importedID(for name: String) -> String {
        let slug = ITermColors.slug(name)
        let digest = digest(of: name)
        return slug.isEmpty
            ? importedIDPrefix + digest
            : "\(importedIDPrefix)\(slug)-\(digest)"
    }

    /// Four base-36 characters of an FNV-1a hash of the name.
    ///
    /// `hashValue` cannot be used here: Swift seeds it per process, so the same
    /// file would be handed a different identifier on every launch and the
    /// selection would be lost each time the app started.
    private static func digest(of name: String) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in name.utf8 {
            hash ^= UInt32(byte)
            hash &*= 16_777_619
        }

        // 36⁴, so the result is never longer than the four characters kept.
        let base36 = String(hash % 1_679_616, radix: 36)
        return String(repeating: "0", count: 4 - base36.count) + base36
    }

    /// The themes that ship with the app, in catalog order.
    let bundled: [TerminalTheme]

    /// The themes the user imported, sorted by name.
    @Published private(set) var imported: [TerminalTheme] = []

    /// Callbacks to run after an import or a removal, so the open terminal can
    /// repaint: the selected theme may now resolve to different colours, or to
    /// none.
    ///
    /// Registered rather than assigned. More than one observer is legitimate —
    /// the settings model repaints, and a preview or a second window may want
    /// the same news — and a single property meant whichever was set last
    /// silently took the news away from every other one.
    private var changeHandlers: [UUID: () -> Void] = [:]

    /// Registers `handler` to run after the next import or removal.
    ///
    /// The returned token is only needed to withdraw it again with
    /// ``removeOnChange(_:)``; keeping a registration for as long as the
    /// observer lives is the normal case.
    @discardableResult
    func onChange(_ handler: @escaping () -> Void) -> UUID {
        let token = UUID()
        changeHandlers[token] = handler
        return token
    }

    /// Stops calling a handler registered with ``onChange(_:)``.
    ///
    /// A model that is thrown away has to withdraw: registrations outlive it,
    /// so a `[weak self]` capture would otherwise go on being called into
    /// nothing for the rest of the process's life.
    func removeOnChange(_ token: UUID) {
        changeHandlers.removeValue(forKey: token)
    }

    /// How many handlers are registered.
    ///
    /// A registration outlives the object that made it unless that object
    /// withdraws it, so this is what a leak of them shows up in.
    var changeHandlerCount: Int {
        changeHandlers.count
    }

    private func notifyChange() {
        for handler in changeHandlers.values {
            handler()
        }
    }

    /// Every theme the picker shows: the imported ones first, because they are
    /// the ones the user just added, then the bundled catalog.
    var all: [TerminalTheme] {
        imported + bundled
    }

    /// Imported themes by identifier, for the file each one came from.
    private var fileURLs: [String: URL] = [:]

    private let directory: URL

    init(bundled: [TerminalTheme] = TerminalTheme.catalog, directory: URL = ThemeLibrary.directory) {
        self.bundled = bundled
        self.directory = directory
        reload()
    }

    // MARK: - Lookup

    /// The theme with this identifier, or the default theme.
    ///
    /// Falling back is what makes deleting the selected theme safe, and what
    /// keeps a `UserDefaults` value written before an import path moved from
    /// turning into an empty terminal.
    func theme(id: String) -> TerminalTheme {
        all.first { $0.id == id } ?? bundled.first ?? TerminalTheme.guac
    }

    /// The file behind an imported theme, or nil for a bundled one.
    func fileURL(for theme: TerminalTheme) -> URL? {
        fileURLs[theme.id]
    }

    func isImported(_ theme: TerminalTheme) -> Bool {
        fileURLs[theme.id] != nil
    }

    // MARK: - Importing

    /// The outcome of one import, in terms the picker can show.
    struct ImportSummary: Sendable {
        struct Failure: Sendable {
            /// The name the user saw in the open panel, or dropped.
            let file: String
            let reason: String
        }

        var importedIDs: [String] = []
        var importedNames: [String] = []
        var failures: [Failure] = []

        var isEmpty: Bool {
            importedNames.isEmpty && failures.isEmpty
        }

        /// The first scheme that made it in, so the picker can select it and
        /// show the user what they just imported.
        var firstImportedID: String? {
            importedIDs.first
        }

        /// One line for the picker's footer or an alert.
        var message: String {
            func list(_ names: [String]) -> String {
                names.count == 1 ? names[0] : "\(names.count) themes"
            }

            if failures.isEmpty {
                if importedNames.count == 1 {
                    return "Imported \(importedNames[0])."
                }
                return "Imported \(list(importedNames))."
            }

            let problems = failures
                .prefix(2)
                .map { "\($0.file): \($0.reason)" }
                .joined(separator: "; ")
            let more = failures.count > 2 ? " and \(failures.count - 2) more" : ""

            guard !importedNames.isEmpty else {
                return "Nothing imported. \(problems)\(more)."
            }
            return "Imported \(list(importedNames)); skipped \(problems)\(more)."
        }
    }

    /// Copies `.itermcolors` files into the library and adds them to the list.
    ///
    /// Each file is validated before anything is written, so a folder of
    /// half-valid schemes imports the good ones and reports the rest instead of
    /// leaving broken files behind. Re-importing a file with the same name
    /// replaces it, which is the natural way to pick up an upstream fix.
    @discardableResult
    func importThemes(from urls: [URL]) -> ImportSummary {
        var summary = ImportSummary()
        guard !urls.isEmpty else { return summary }

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for url in urls {
            let fileName = url.lastPathComponent
            guard url.pathExtension.lowercased() == ITermColors.pathExtension else {
                summary.failures.append(
                    .init(file: fileName, reason: "not an .\(ITermColors.pathExtension) file")
                )
                continue
            }

            // Parse before copying: a file that cannot be read is not worth
            // putting in the library, and the reason is what the user needs.
            let scheme: ParsedScheme
            do {
                scheme = try ITermColors.parse(contentsOf: url)
            } catch {
                summary.failures.append(
                    .init(file: fileName, reason: message(for: error))
                )
                continue
            }

            let destination = directory.appendingPathComponent(fileName, isDirectory: false)
            if url.standardizedFileURL != destination.standardizedFileURL {
                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.copyItem(at: url, to: destination)
                } catch {
                    summary.failures.append(
                        .init(file: fileName, reason: error.localizedDescription)
                    )
                    continue
                }
            }

            summary.importedNames.append(scheme.name)
        }

        guard !summary.importedNames.isEmpty else { return summary }

        reload()

        // Identifiers are assigned in `reload()`, from the filenames. Reporting
        // the ones that belong to the files just written means matching on the
        // name the file gives a scheme, which is its stem.
        let importedNames = Set(summary.importedNames)
        summary.importedIDs = imported
            .filter { importedNames.contains($0.name) }
            .map(\.id)

        notifyChange()
        return summary
    }

    // MARK: - Removing

    /// Moves the file behind an imported theme to the Trash.
    ///
    /// Trash rather than unlinking: removing a theme is a click on a document
    /// the user brought with them, so it must be recoverable in the Finder.
    /// Returns false for a bundled theme, and for a file that is already gone —
    /// the list is reloaded either way, so the picker cannot get stuck showing
    /// a scheme whose file disappeared underneath it.
    @discardableResult
    func remove(_ theme: TerminalTheme) -> Bool {
        guard let url = fileURLs[theme.id] else { return false }

        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // Already gone: reloading is all that is left to do.
        } catch {
            NSLog("[GuacTerm] could not remove %@: %@", url.path, error.localizedDescription)
            return false
        }

        reload()
        notifyChange()
        return true
    }

    /// Shows the scheme's file in the Finder, which is also how a user gets at
    /// the original to edit it.
    func reveal(_ theme: TerminalTheme) {
        guard let url = fileURLs[theme.id] else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Reading the library

    /// Rebuilds ``imported`` from whatever is in the directory now.
    ///
    /// Filenames are sorted before identifiers are handed out, so the same set
    /// of files always produces the same identifiers — `UserDefaults` points at
    /// one of them, and a scheme must not lose its selection because the
    /// filesystem returned the directory in another order.
    private func reload() {
        fileURLs = [:]

        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        let schemes = files
            .filter { $0.pathExtension.lowercased() == ITermColors.pathExtension }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var usedIDs = Set(bundled.map(\.id))
        var themes: [TerminalTheme] = []
        themes.reserveCapacity(schemes.count)

        for file in schemes {
            let scheme: ParsedScheme
            do {
                scheme = try ITermColors.parse(contentsOf: file)
            } catch {
                NSLog(
                    "[GuacTerm] skipping %@: %@",
                    file.lastPathComponent, message(for: error)
                )
                continue
            }

            let baseID = Self.importedID(for: scheme.name)
            var id = baseID
            var suffix = 2
            while !usedIDs.insert(id).inserted {
                id = "\(baseID)-\(suffix)"
                suffix += 1
            }

            themes.append(
                TerminalTheme(
                    id: id,
                    name: scheme.name,
                    background: scheme.background,
                    foreground: scheme.foreground,
                    cursor: scheme.cursor,
                    ansi: scheme.ansi
                )
            )
            fileURLs[id] = file
        }

        imported = themes.sorted(by: TerminalTheme.nameOrder)
    }

    /// `LocalizedError` descriptions are what the failing file is reported with;
    /// the fallback keeps an unexpected error readable rather than empty.
    private func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
