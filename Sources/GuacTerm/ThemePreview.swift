import AppKit
import SwiftUI

/// A live sample of the selected ``TerminalTheme``: ANSI palette, a prompt line
/// and the cursor block, on the theme's own background.
struct ThemePreview: View {
    let theme: TerminalTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(0 ..< 2, id: \.self) { row in
                    HStack(spacing: 3) {
                        ForEach(0 ..< 8, id: \.self) { column in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(swatch(row * 8 + column))
                                .frame(width: 16, height: 9)
                        }
                    }
                }
            }

            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color(nsColor: theme.nsCursor))
                    .frame(width: 7, height: 13)
                Text("‾/code/guacterm → make run")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(nsColor: theme.nsForeground))
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: theme.nsBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the \(theme.name) theme")
    }

    private func swatch(_ index: Int) -> Color {
        let palette = theme.nsAnsi
        guard palette.indices.contains(index) else {
            return Color(nsColor: theme.nsForeground)
        }
        return Color(nsColor: palette[index])
    }
}
