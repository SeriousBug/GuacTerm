import AppKit
import SwiftTerm

/// A color scheme: window background, default text, cursor and the 16 ANSI
/// colors programs actually ask for.
struct TerminalTheme: Identifiable, Hashable, Sendable {

    let id: String
    let name: String

    /// Light themes get a light window border and a dark cursor.
    let isLight: Bool

    let background: String
    let foreground: String
    let cursor: String

    /// Exactly 16 hex colors, ANSI 0-15.
    let ansi: [String]

    // MARK: - Colors

    var nsBackground: NSColor { NSColor(hex: background) }
    var nsForeground: NSColor { NSColor(hex: foreground) }
    var nsCursor: NSColor { NSColor(hex: cursor) }
    var nsAnsi: [NSColor] { ansi.map { NSColor(hex: $0) } }

    /// The palette SwiftTerm expects from `installColors(_:)`.
    var terminalPalette: [SwiftTerm.Color] {
        nsAnsi.map { SwiftTerm.Color(nsColor: $0) }
    }

    // MARK: - Catalog access

    /// The theme used when nothing is configured, and the fallback for an
    /// identifier written by an older version.
    static let defaultThemeID = "guac"

    static func theme(id: String) -> TerminalTheme {
        catalog.first { $0.id == id } ?? catalog[0]
    }
}

extension NSColor {

    /// Accepts `#RRGGBB`, `RRGGBB` and `#RGB`.
    convenience init(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 3 {
            text = text.map { "\($0)\($0)" }.joined()
        }

        var value: UInt64 = 0
        Scanner(string: text).scanHexInt64(&value)
        if text.count != 6 { value = 0 }

        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#000000" }
        let red = Int((rgb.redComponent * 255).rounded())
        let green = Int((rgb.greenComponent * 255).rounded())
        let blue = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
