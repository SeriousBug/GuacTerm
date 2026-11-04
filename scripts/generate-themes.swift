//
//  generate-themes.swift
//  GuacTerm
//
//  Writes Resources/Themes.json — the catalog GuacTerm bundles — from a checkout
//  of the iTerm2-Color-Schemes collection.
//
//  This is a command-line tool, not part of the app, but it is Swift and it
//  compiles in Sources/GuacTerm/ITermColors.swift rather than re-implementing
//  it. That is the point: reading a `.itermcolors` file has exactly one
//  implementation, so an imported scheme and the same scheme read out of the
//  bundle cannot disagree about a colour, a cursor fallback, or a slug.
//
//  Normally reached through ./scripts/themes.sh, which fetches the pinned
//  upstream commit first:
//
//      ./scripts/themes.sh            # regenerate Resources/Themes.json
//      ./scripts/themes.sh --check    # fail when it drifts from that commit
//
//  Run directly (after scripts/themes.sh has populated the cache):
//
//      swiftc -parse-as-library -swift-version 6 \
//          Sources/GuacTerm/ITermColors.swift scripts/generate-themes.swift \
//          -o build/tools/generate-themes
//      build/tools/generate-themes --source <clone> --output <file>
//
//  The output is deterministic — same source, same bytes — and sorted by name,
//  one scheme per line, so regenerating shows up in a diff as the schemes that
//  actually changed.
//
//  Exit status: 0 written, 1 too many schemes skipped, 2 nothing usable to read,
//  3 the JSON did not round-trip (a bug in here, not in the source).
//

import Foundation

@main
struct GenerateThemes {

    /// Skipping more schemes than this fraction of the source files is an
    /// error, so a broken or partial checkout fails loudly instead of quietly
    /// shrinking the catalog.
    static let maxSkipRate = 0.05

    static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    // MARK: - One scheme on its way into the catalog

    /// A scheme, once it has an identifier.
    struct Entry: NamedTheme {
        let id: String
        let scheme: ParsedScheme

        /// The file it came from, which is also the last tiebreaker when two
        /// schemes want the same identifier.
        let fileName: String

        var name: String { scheme.name }
    }

    // MARK: - Entry point

    static func main() {
        exit(run(Array(CommandLine.arguments.dropFirst())))
    }

    static func run(_ arguments: [String]) -> Int32 {
        if arguments.contains("-h") || arguments.contains("--help") {
            print(usage)
            return 0
        }
        guard let options = Options(arguments) else { return 2 }

        let files = schemeFiles(in: options.source)
        guard !files.isEmpty else {
            standardError.write(
                """
                error: no \(ITermColors.pathExtension) files found in \(options.source.path)
                       fetch the pinned collection with:
                         ./scripts/themes.sh   # or: make themes
                       or point --source at your own clone of
                         https://github.com/mbadolato/iTerm2-Color-Schemes.git

                """
            )
            return 2
        }

        // ------------------------------------------------------------------ read
        var read: [(fileName: String, scheme: ParsedScheme)] = []
        var skipped: [(fileName: String, reason: String)] = []
        read.reserveCapacity(files.count)

        for file in files {
            do {
                read.append((file.lastPathComponent, try ITermColors.parse(contentsOf: file)))
            } catch {
                skipped.append((file.lastPathComponent, message(for: error)))
            }
        }

        // ------------------------------------------------------------ assign ids
        //
        // Grouped by the identifier the name slugs to, so a collision is
        // resolved in a fixed order: the scheme whose name is already a clean
        // slug keeps the plain id and the others get "-2", "-3", ... in name
        // order. Everything is driven by sorted keys, so the result never
        // depends on the order the filesystem returned the files in.
        var groups: [String: [(fileName: String, scheme: ParsedScheme)]] = [:]
        for item in read {
            groups[ITermColors.slug(item.scheme.name), default: []].append(item)
        }

        var usedIDs = Set<String>()
        var entries: [Entry] = []
        var collisions: [(name: String, fileName: String, base: String, id: String)] = []
        entries.reserveCapacity(read.count)

        for base in groups.keys.sorted() {
            let members = (groups[base] ?? []).sorted { lhs, rhs in
                let left = lhs.scheme, right = rhs.scheme
                let leftRank = canonicalRank(left.name), rightRank = canonicalRank(right.name)
                if leftRank != rightRank { return leftRank < rightRank }
                if left.name.lowercased() != right.name.lowercased() {
                    return left.name.lowercased() < right.name.lowercased()
                }
                if left.name != right.name { return left.name < right.name }
                return lhs.fileName < rhs.fileName
            }

            for member in members {
                let (id, suffix) = uniqueID(base, used: &usedIDs)
                if suffix != nil {
                    collisions.append(
                        (member.scheme.name, member.fileName, base, id)
                    )
                }
                entries.append(Entry(id: id, scheme: member.scheme, fileName: member.fileName))
            }
        }

        entries.sort(by: Entry.nameOrder)

        // ---------------------------------------------------------------- write
        let text = render(entries)

        // Cheap self-check: what was written must parse back to the same count.
        let reparsed = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [Any]
        guard let reparsed, reparsed.count == entries.count else {
            standardError.write("error: internal error, JSON did not round-trip\n")
            return 3
        }

        do {
            try FileManager.default.createDirectory(
                at: options.output.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try text.write(to: options.output, atomically: false, encoding: .utf8)
        } catch {
            standardError.write("error: could not write \(options.output.path): \(error)\n")
            return 3
        }

        report(
            options: options,
            text: text,
            total: files.count,
            written: entries.count,
            skipped: skipped,
            collisions: collisions,
            cursorFallbacks: read.filter(\.scheme.cursorIsFallback).map(\.fileName)
        )

        let skipRate = files.isEmpty ? 0 : Double(skipped.count) / Double(files.count)
        if skipRate > maxSkipRate {
            standardError.write(
                String(
                    format: "error: skipped %.2f%% of the schemes, above the %.0f%% limit\n",
                    skipRate * 100,
                    maxSkipRate * 100
                )
            )
            return 1
        }

        return 0
    }

    // MARK: - Arguments

    struct Options {
        var source: URL
        var output: URL

        /// `nil` means the arguments were not understood, and the caller exits 2.
        init?(_ arguments: [String]) {
            var source = Self.defaultSource
            var output = Self.defaultOutput

            var remaining = arguments[...]
            while let argument = remaining.first {
                remaining = remaining.dropFirst()
                switch argument {
                case "--source", "--output":
                    guard let value = remaining.first else { return nil }
                    remaining = remaining.dropFirst()
                    let url = URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
                    if argument == "--source" { source = url } else { output = url }
                default:
                    return nil
                }
            }

            self.source = source
            self.output = output
        }

        /// The cache ./scripts/themes.sh fills with the pinned upstream commit.
        static var defaultSource: URL {
            repositoryRoot
                .appendingPathComponent("build/upstream/iterm-schemes", isDirectory: true)
        }

        static var defaultOutput: URL {
            repositoryRoot.appendingPathComponent("Resources/Themes.json", isDirectory: false)
        }
    }

    static var usage: String {
        """
        usage: generate-themes [--source DIR] [--output FILE]

        Writes the GuacTerm theme catalog from *.itermcolors files.

          --source DIR    a clone of iTerm2-Color-Schemes, or a directory of
                          *.itermcolors files
                          (default: build/upstream/iterm-schemes)
          --output FILE   JSON file to write
                          (default: Resources/Themes.json in the repository)
        """
    }

    // MARK: - Finding the source files

    /// Every `*.itermcolors` file to read.
    ///
    /// Takes either the repository root (`<source>/schemes/*.itermcolors`) or a
    /// directory of scheme files directly. Sorted case-sensitively so the order
    /// identifiers are handed out in does not depend on the filesystem.
    static func schemeFiles(in source: URL) -> [URL] {
        let nested = source.appendingPathComponent("schemes", isDirectory: true)
        var isDirectory: ObjCBool = false
        let directory = FileManager.default.fileExists(atPath: nested.path, isDirectory: &isDirectory)
            && isDirectory.boolValue ? nested : source

        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return []
        }

        return names
            .filter { $0.hasSuffix("." + ITermColors.pathExtension) && !$0.hasPrefix(".") }
            .sorted()
            .map { directory.appendingPathComponent($0, isDirectory: false) }
    }

    // MARK: - Identifiers

    /// 0 when the name is already a clean lowercase slug, 1 otherwise.
    ///
    /// Used to resolve id collisions in favour of the scheme that needs no
    /// mangling: "Dracula" keeps `dracula` and "Dracula+" becomes `dracula-2`.
    static func canonicalRank(_ name: String) -> Int {
        ITermColors.slug(name) == name.lowercased() ? 0 : 1
    }

    /// An identifier that is not in `used` yet, plus the suffix when it had to
    /// change.
    static func uniqueID(_ base: String, used: inout Set<String>) -> (id: String, suffix: Int?) {
        if !base.isEmpty, !used.contains(base) {
            used.insert(base)
            return (base, nil)
        }

        let stem = base.isEmpty ? "theme" : base
        var suffix = 2
        while used.contains("\(stem)-\(suffix)") {
            suffix += 1
        }
        let id = "\(stem)-\(suffix)"
        used.insert(id)
        return (id, suffix)
    }

    // MARK: - Rendering

    /// One scheme per line: compact enough to stay small, one line per scheme so
    /// the file diffs by scheme rather than by character.
    static func render(_ entries: [Entry]) -> String {
        var lines: [String] = []
        lines.reserveCapacity(entries.count)

        for entry in entries {
            let ansi = entry.scheme.ansi.map(jsonString).joined(separator: ",")
            lines.append(
                "  {\"id\":\(jsonString(entry.id))"
                    + ",\"name\":\(jsonString(entry.name))"
                    + ",\"bg\":\(jsonString(entry.scheme.background))"
                    + ",\"fg\":\(jsonString(entry.scheme.foreground))"
                    + ",\"cursor\":\(jsonString(entry.scheme.cursor))"
                    + ",\"ansi\":[\(ansi)]}"
            )
        }

        return "[\n" + lines.joined(separator: ",\n") + "\n]\n"
    }

    /// A JSON string literal, escaped the way Python's `json.dumps` does it.
    ///
    /// Scheme names are ASCII today, but the catalog is regenerated from someone
    /// else's repository: escaping every non-ASCII scalar now means a scheme
    /// called "Ünïcode" cannot turn a one-line diff into a change of the whole
    /// file later, and keeps the output identical to what the catalog was
    /// originally generated with.
    static func jsonString(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else if scalar.value < 0x7F {
                    out.unicodeScalars.append(scalar)
                } else if scalar.value <= 0xFFFF {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    // Above the BMP: a surrogate pair, as JSON requires.
                    let value = scalar.value - 0x1_0000
                    out += String(format: "\\u%04x\\u%04x", 0xD800 + (value >> 10), 0xDC00 + (value & 0x3FF))
                }
            }
        }
        return out + "\""
    }

    // MARK: - Reporting

    static func report(
        options: Options,
        text: String,
        total: Int,
        written: Int,
        skipped: [(fileName: String, reason: String)],
        collisions: [(name: String, fileName: String, base: String, id: String)],
        cursorFallbacks: [String]
    ) {
        let size = text.utf8.count
        let skipRate = total == 0 ? 0 : Double(skipped.count) / Double(total)

        print("source:  \(options.source.path)")
        print(String(format: "output:  %@  (%d bytes, %.1f KiB)", options.output.path, size, Double(size) / 1024))
        print("total:   \(total) files")
        print("written: \(written) themes")
        print(String(format: "skipped: %d (%.2f%%)", skipped.count, skipRate * 100))
        for item in skipped {
            print("  - \(item.fileName): \(item.reason)")
        }

        print("duplicate ids disambiguated: \(collisions.count)")
        for collision in collisions {
            let base = collision.base.isEmpty ? "(nothing usable)" : collision.base
            print("  - \"\(collision.name)\" (\(collision.fileName)): \"\(base)\" -> \"\(collision.id)\"")
        }

        // Schemes with no usable "Cursor Color": the foreground stood in.
        if !cursorFallbacks.isEmpty {
            let shown = cursorFallbacks.prefix(5).joined(separator: ", ")
            let more = cursorFallbacks.count > 5 ? "..." : ""
            print("cursor fell back to foreground: \(cursorFallbacks.count) (\(shown)\(more))")
        }
    }

    // MARK: - Helpers

    static var standardError: FileHandle { FileHandle.standardError }

    static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

extension FileHandle {
    /// Writes a string to this handle, ignoring failures: it is used for error
    /// output, where there is nothing useful left to do if stderr is gone.
    func write(_ text: String) {
        if let data = text.data(using: .utf8) {
            try? write(contentsOf: data)
        }
    }
}
