//
//  ITermColors.swift
//  GuacTerm
//
//  Reads iTerm2 `.itermcolors` colour schemes at runtime.
//
//  This file is the one implementation of that conversion, used twice: the app
//  imports schemes with it at runtime (`ThemeLibrary`), and the command-line
//  generator that writes Resources/Themes.json compiles it in directly
//  (`scripts/generate-themes.swift`). A scheme imported from a file therefore
//  looks exactly like the copy that ships in the bundle — same 16 ANSI slots,
//  same fallback to the foreground when a scheme has no cursor colour, same
//  rounding — because it is the same code, not a port of it.
//
//  Foundation only, and no AppKit, precisely so it can be compiled on its own:
//  `swiftc Sources/GuacTerm/ITermColors.swift scripts/generate-themes.swift`.
//  Anything app-only added here would break the generator build.
//

import Foundation

/// A theme as a list needs it: a display name and a stable identifier.
///
/// Shared with the generator so the order Resources/Themes.json is written in
/// and the order the picker lists it in are the same rule, not two lookalikes.
/// `TerminalTheme` and the generator's own entry type both conform.
protocol NamedTheme {
    var id: String { get }
    var name: String { get }
}

extension NamedTheme {

    /// Case-insensitive by name, then by the exact name and identifier, so the
    /// order is total and a list is stable whatever it was built from.
    ///
    /// Scheme names are ASCII today, which is what makes this agree with the
    /// Python generator this rule came from; the tiebreakers keep it total even
    /// if that stops being true.
    static func nameOrder(_ lhs: Self, _ rhs: Self) -> Bool {
        let left = lhs.name.lowercased()
        let right = rhs.name.lowercased()
        if left != right { return left < right }
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        return lhs.id < rhs.id
    }
}

/// The colours of one scheme, straight out of a `.itermcolors` file.
///
/// Colours are sRGB `#RRGGBB` uppercase hex; `ansi` always holds exactly 16
/// values, ANSI 0-15. Turning this into a ``TerminalTheme`` is `ThemeLibrary`'s
/// job, because that is where it gains an identifier and a place in the list.
struct ParsedScheme: Equatable, Sendable {
    let name: String
    let background: String
    let foreground: String
    let cursor: String
    let ansi: [String]

    /// True when the file had no usable cursor colour and ``cursor`` is the
    /// foreground standing in. Only the generator's report shows this; the UI
    /// draws the colour it ends up with either way.
    let cursorIsFallback: Bool
}

/// Why a file could not be read as a scheme.
///
/// The messages are shown to the user next to the file's name, so they name the
/// missing piece rather than the parser's internals.
enum ITermColorsError: LocalizedError, Equatable {
    case notAPropertyList
    case notAScheme
    case missingKey(String)
    case malformedColor(String)

    var errorDescription: String? {
        switch self {
        case .notAPropertyList:
            return "not a property list"
        case .notAScheme:
            return "not an iTerm2 colour scheme"
        case .missingKey(let key):
            return "no \(key)"
        case .malformedColor(let key):
            return "\(key) is not a colour"
        }
    }
}

enum ITermColors {

    /// The filename extension iTerm2 uses when it exports a scheme.
    static let pathExtension = "itermcolors"

    // MARK: - Parsing

    /// Parses one file, naming the scheme after it: `Nord.itermcolors` becomes
    /// "Nord". The stem is kept verbatim, exactly as the generator does, so the
    /// same file gives the same name however it is imported.
    static func parse(contentsOf url: URL) throws -> ParsedScheme {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ITermColorsError.notAPropertyList
        }
        return try parse(data, name: url.deletingPathExtension().lastPathComponent)
    }

    /// Parses the bytes of a `.itermcolors` file.
    ///
    /// `PropertyListSerialization` handles both the XML form iTerm2 writes and
    /// the binary form some tools emit, so a file only has to be a plist.
    static func parse(_ data: Data, name: String) throws -> ParsedScheme {
        let propertyList: Any
        do {
            propertyList = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            )
        } catch {
            throw ITermColorsError.notAPropertyList
        }

        guard let scheme = propertyList as? [String: Any] else {
            throw ITermColorsError.notAScheme
        }

        let ansi = try ansiKeys.map { key in try hex(scheme, key) }
        let background = try hex(scheme, backgroundKey)
        let foreground = try hex(scheme, foregroundKey)

        // The cursor is cosmetic: a scheme without a usable one is still a
        // usable scheme, so it borrows the foreground instead of being refused.
        let declaredCursor = try? hex(scheme, cursorKey)
        let cursor = declaredCursor ?? foreground

        return ParsedScheme(
            name: name,
            background: background,
            foreground: foreground,
            cursor: cursor,
            ansi: ansi,
            cursorIsFallback: declaredCursor == nil
        )
    }

    // MARK: - Identifiers

    /// `"Solarized Dark"` -> `"solarized-dark"`.
    ///
    /// The rule Resources/Themes.json was originally written with: lowercase ASCII
    /// alphanumerics kept, every other run collapsed into one `-` and trimmed.
    /// Identifiers end up in `UserDefaults`, so they have to be stable for a
    /// given filename.
    static func slug(_ text: String) -> String {
        let folded = text
            .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: nil)
            .lowercased()

        var slug = ""
        var separatorPending = false

        for scalar in folded.unicodeScalars {
            let isAlphanumeric = (scalar.value >= 0x61 && scalar.value <= 0x7A)   // a-z
                || (scalar.value >= 0x30 && scalar.value <= 0x39)                // 0-9
            if isAlphanumeric {
                if separatorPending, !slug.isEmpty {
                    slug.append("-")
                }
                separatorPending = false
                slug.unicodeScalars.append(scalar)
            } else {
                separatorPending = true
            }
        }

        return slug
    }

    // MARK: - Keys

    /// The plist keys an iTerm2 scheme uses. `0x` rather than `%d` padding
    /// matches both iTerm2's export and the generator.
    private static let ansiKeys = (0..<16).map { "Ansi \($0) Color" }
    private static let backgroundKey = "Background Color"
    private static let foregroundKey = "Foreground Color"
    private static let cursorKey = "Cursor Color"
    private static let componentKeys = ["Red Component", "Green Component", "Blue Component"]

    // MARK: - Colours

    /// One `{Red,Green,Blue} Component` dictionary as `#RRGGBB`.
    private static func hex(_ scheme: [String: Any], _ key: String) throws -> String {
        guard let value = scheme[key] else {
            throw ITermColorsError.missingKey(key)
        }
        guard let colour = value as? [String: Any] else {
            throw ITermColorsError.malformedColor(key)
        }

        var channels: [Int] = []
        channels.reserveCapacity(componentKeys.count)

        for component in componentKeys {
            // A plist boolean arrives as an NSNumber too, and `true` would
            // quietly become 255, so booleans are rejected explicitly.
            guard let number = colour[component] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID()
            else {
                throw ITermColorsError.malformedColor(key)
            }
            channels.append(byte(number.doubleValue))
        }

        return String(format: "#%02X%02X%02X", channels[0], channels[1], channels[2])
    }

    /// A 0...1 colour component as 0...255, rounded half away from zero.
    ///
    /// Matches `_clamp_byte` in the generator, including its tolerance: files in
    /// the wild sometimes store 0...255 integers where iTerm2 stores 0...1
    /// fractions, and clamping (rather than scaling) gives those the same result
    /// the bundled catalog would have.
    private static func byte(_ component: Double) -> Int {
        let scaled = component * 255 + 0.5
        guard scaled.isFinite else { return 0 }
        if scaled <= 0 { return 0 }
        if scaled >= 255 { return 255 }
        return Int(scaled)
    }
}
