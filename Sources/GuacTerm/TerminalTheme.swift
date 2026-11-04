import AppKit
import SwiftTerm

/// A color scheme: window background, default text, cursor and the 16 ANSI
/// colors programs actually ask for.
struct TerminalTheme: Identifiable, Hashable, Sendable, NamedTheme {
    let id: String
    let name: String

    let background: String
    let foreground: String
    let cursor: String

    /// Exactly 16 hex colors, ANSI 0-15.
    let ansi: [String]

    /// Light themes get a light window border and a dark cursor.
    ///
    /// Derived rather than stored: the same scheme has to be judged the same way
    /// whether it was imported from a file or read out of the bundled catalog,
    /// and the only way to guarantee that is to keep one rule in one place. See
    /// ``isLight(background:)``.
    var isLight: Bool {
        Self.isLight(background: background)
    }

    // MARK: - Colors

    var nsBackground: NSColor {
        NSColor(hex: background)
    }

    var nsForeground: NSColor {
        NSColor(hex: foreground)
    }

    var nsCursor: NSColor {
        NSColor(hex: cursor)
    }

    var nsAnsi: [NSColor] {
        ansi.map { NSColor(hex: $0) }
    }

    /// The palette SwiftTerm expects from `installColors(_:)`.
    var terminalPalette: [SwiftTerm.Color] {
        nsAnsi.map { SwiftTerm.Color(nsColor: $0) }
    }

    // MARK: - Judging colors

    /// A colour split into its three 0...255 channels.
    private struct RGB {
        let red: Int
        let green: Int
        let blue: Int
    }

    /// True for `#RRGGBB` with exactly six hex digits (a leading `#` is
    /// optional, since a hand-edited file may leave it off).
    static func isHexColor(_ text: String) -> Bool {
        rgbComponents(text) != nil
    }

    /// A background this bright wants dark text, so the window gets a light
    /// chrome: WCAG relative luminance above 0.5.
    static func isLight(background hex: String) -> Bool {
        relativeLuminance(of: hex) > 0.5
    }

    /// `#RRGGBB` -> channels, or nil when malformed.
    private static func rgbComponents(_ text: String) -> RGB? {
        var digits = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        if digits.first == "#" {
            digits = digits.dropFirst()
        }
        // `UInt32(_:radix:)` takes a leading sign, and six digits plus a sign
        // would otherwise pass as six hex digits and then draw as black.
        guard digits.count == 6,
              digits.allSatisfy(\.isHexDigit),
              let value = UInt32(digits, radix: 16)
        else { return nil }
        return RGB(
            red: Int((value >> 16) & 0xFF),
            green: Int((value >> 8) & 0xFF),
            blue: Int(value & 0xFF)
        )
    }

    /// WCAG relative luminance, 0 (black) ... 1 (white).
    private static func relativeLuminance(of hex: String) -> Double {
        guard let rgb = rgbComponents(hex) else { return 0 }
        return 0.2126 * linearComponent(rgb.red)
            + 0.7152 * linearComponent(rgb.green)
            + 0.0722 * linearComponent(rgb.blue)
    }

    /// Undoes the sRGB transfer function for one 0...255 channel.
    private static func linearComponent(_ value: Int) -> Double {
        let channel = Double(value) / 255
        return channel <= 0.04045
            ? channel / 12.92
            : pow((channel + 0.055) / 1.055, 2.4)
    }

    // MARK: - Catalog access

    /// The theme used when nothing is configured, and the fallback for an
    /// identifier written by an older version, or for an imported theme whose
    /// file has since been removed.
    static let defaultThemeID = "guac"
}

extension NSColor {
    /// Accepts `#RRGGBB`, `RRGGBB` and `#RGB`.
    convenience init(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") {
            text.removeFirst()
        }
        if text.count == 3 {
            text = text.map { "\($0)\($0)" }.joined()
        }

        var value: UInt64 = 0
        Scanner(string: text).scanHexInt64(&value)
        if text.count != 6 {
            value = 0
        }

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
