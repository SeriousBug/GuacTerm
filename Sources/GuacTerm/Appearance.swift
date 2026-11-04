//
//  Appearance.swift
//  GuacTerm
//
//  The two answers to "how should this look": the mode the app's own windows
//  follow, and the pair of terminal schemes behind it.
//

import AppKit
import Foundation

/// How GuacTerm's own windows and menus look, and which of the two terminal
/// schemes is in effect.
///
/// The chrome follows the mode as it is set. The terminal follows it through
/// ``Settings/themeSlot``: a light appearance paints the light scheme, a dark
/// one the dark scheme, and ``system`` — shown as "Auto" — hands the choice to
/// macOS, which may switch it while the panel is open.
enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .system: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` means "follow the system".
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Which of the two color schemes a selection is about.
///
/// Two schemes rather than one: following macOS into dark mode is supposed to
/// hand the terminal a scheme that matches the rest of the desktop, not the
/// same colors it had.
enum ThemeSlot: String, CaseIterable, Identifiable, Sendable {
    case light
    case dark

    var id: String {
        rawValue
    }

    /// The label the settings pane shows.
    var label: String {
        switch self {
        case .light: "Light Theme"
        case .dark: "Dark Theme"
        }
    }

    /// The scheme used when nothing is configured for this slot.
    var defaultThemeID: String {
        switch self {
        case .light: TerminalTheme.defaultLightThemeID
        case .dark: TerminalTheme.defaultThemeID
        }
    }
}
