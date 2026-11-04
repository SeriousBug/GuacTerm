import AppKit
import Carbon.HIToolbox
@testable import GuacTerm
import XCTest

// Fixtures shared by the suites. Nothing here asserts anything: these are how a
// test builds the messy inputs the app has to survive — a hand-written
// `.itermcolors` file, a defaults domain with yesterday's garbage in it, a
// program on disk that must not accidentally be found.

// MARK: - Temporary directories

/// A directory of its own for one test, removed again in its `tearDown`.
///
/// Under the system temporary directory rather than the user's real theme
/// library, so a test that imports or removes a scheme never touches anything a
/// person would miss.
final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GuacTermTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// Writes a scheme into the directory and returns its URL.
    @discardableResult
    func write(_ contents: Data, as fileName: String) throws -> URL {
        let fileURL = url.appendingPathComponent(fileName, isDirectory: false)
        try contents.write(to: fileURL)
        return fileURL
    }

    /// Writes a valid scheme that parses, named after `name`.
    @discardableResult
    func writeScheme(named name: String, background: String = "#101010") throws -> URL {
        try write(
            ThemePlist.scheme(background: background),
            as: name.hasSuffix(".itermcolors") ? name : "\(name).itermcolors"
        )
    }

    func contents() throws -> [String] {
        try FileManager.default
            .contentsOfDirectory(atPath: url.path)
            .sorted()
    }
}

// MARK: - User defaults

/// A defaults domain no other process uses, forgotten again when the test ends.
///
/// `UserDefaults.standard` would carry whatever the developer's own GuacTerm is
/// configured with, and would leave a plist behind in ~/Library/Preferences.
final class TemporaryDefaults {
    let suiteName = "GuacTermTests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

// MARK: - iTerm2 colour schemes

/// Builds the property list an `.itermcolors` file holds.
enum ThemePlist {
    /// A component dictionary as iTerm2 writes one: 0...1 fractions.
    static func component(_ value: Double) -> [String: Any] {
        ["Red Component": value, "Green Component": value, "Blue Component": value]
    }

    static func color(red: Double, green: Double, blue: Double) -> [String: Any] {
        ["Red Component": red, "Green Component": green, "Blue Component": blue]
    }

    /// Every key a complete scheme needs, with all sixteen ANSI slots present.
    static func scheme(
        background: String = "#101010",
        foreground: String = "#EEEEEE",
        cursor: String? = "#FFFFFF",
        ansi: [Int]? = nil
    ) -> Data {
        var plist: [String: Any] = [:]
        let slots = ansi ?? Array(0 ..< 16)

        for (index, slot) in slots.enumerated() {
            // A grey ramp: slot N is N/16 of the way from black to white.
            let level = Double(slot) / 16
            plist["Ansi \(index) Color"] = component(level)
        }

        plist["Background Color"] = color(from: background)
        plist["Foreground Color"] = color(from: foreground)
        if let cursor {
            plist["Cursor Color"] = color(from: cursor)
        }

        return serialized(plist)
    }

    /// Splits `#RRGGBB` into the 0...1 components a scheme stores.
    static func color(from hex: String) -> [String: Any] {
        var digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if digits.count == 3 {
            digits = digits.map { "\($0)\($0)" }.joined()
        }
        let value = UInt32(digits, radix: 16) ?? 0
        return color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// The XML form iTerm2 itself writes, which is also the form that can hold
    /// booleans and integers by accident.
    static func serialized(_ plist: [String: Any]) -> Data {
        (try? PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )) ?? Data()
    }
}

// MARK: - Programs on disk

/// Creates a file that passes `isExecutableFile` but is never run.
///
/// Lets the shell setting be pointed at something that exists without the test
/// depending on which programs this machine happens to have installed.
@discardableResult
func makeExecutableFile(named name: String, in directory: URL) throws -> URL {
    let url = directory.appendingPathComponent(name, isDirectory: false)
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: url.path
    )
    return url
}

// MARK: - Keyboard events

/// An `NSEvent` for a key press, so shortcut handling can be driven without a
/// window or a person at the keyboard.
@MainActor
func keyEvent(
    keyCode: UInt16,
    modifiers: NSEvent.ModifierFlags = [],
    characters: String = "t"
) -> NSEvent? {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: modifiers,
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: characters,
        charactersIgnoringModifiers: characters,
        isARepeat: false,
        keyCode: keyCode
    )
}

// MARK: - Environment

/// `ShellEnvironment.make` returns `KEY=value` strings in whatever order the
/// dictionary enumerated in, so an array comparison would flake. This is how a
/// test reads it.
func environmentDictionary(_ entries: [String]) -> [String: String] {
    var result: [String: String] = [:]
    for entry in entries {
        let parts = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { continue }
        result[String(parts[0])] = String(parts[1])
    }
    return result
}
