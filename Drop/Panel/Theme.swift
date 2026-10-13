import SwiftUI

/// Every size the drop zone uses. Colour is neutral at rest; the accent appears only on the target under the cursor.
enum Theme {
    static let columns = 4
    static let tileWidth: CGFloat = 72
    static let spacing: CGFloat = 8
    static let padding: CGFloat = 14
    static let panelCornerRadius: CGFloat = 24
    static let panelWidth: CGFloat = CGFloat(columns) * tileWidth + CGFloat(columns - 1) * spacing + padding * 2

    static let toolIconSize: CGFloat = 44
    static let toolCornerRadius: CGFloat = 12
    static let chipHeight: CGFloat = 32
    static let chipCornerRadius: CGFloat = 9

    /// Gap between the cursor and the panel edge when it appears.
    static let cursorGap: CGFloat = 28
    static let screenMargin: CGFloat = 10

    static let surface = Color.primary.opacity(0.06)
    static let surfaceHover = Color.primary.opacity(0.1)
    static let hairline = Color.primary.opacity(0.07)

    /// Hover and state changes: short and quiet, never springy.
    static let hover = Animation.easeOut(duration: 0.14)
    static let fade = Animation.easeInOut(duration: 0.18)
}

extension View {
    /// Liquid Glass button on macOS 26, a bordered button before.
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else if prominent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
    }
}
