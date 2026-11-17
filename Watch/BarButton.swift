import SwiftUI

/// An icon for a watch toolbar button. On watchOS 26 the button's circle is filled with the
/// tint, so the icon gets its own colour to stay readable on any tint.
struct BarIcon: View {
    let systemName: String
    var body: some View {
        Image(systemName: systemName)
            .foregroundStyle(.white)
    }
}

extension View {
    /// Quiet grey for secondary toolbar buttons; pass a colour for the main action.
    func barTint(_ color: Color = Color(white: 0.3)) -> some View {
        tint(color)
    }
}

extension Color {
    /// A deeper green than `Ink.good` so a white check on it stays readable.
    static let barGreen = Color(hex: 0x2F8A5B)
}
