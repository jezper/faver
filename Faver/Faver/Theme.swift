import SwiftUI

// MARK: - Colours

extension Color {
    /// Dark-charcoal background — #0F0F1A
    static let bg        = Color(red: 0.059, green: 0.059, blue: 0.102)
    /// Card / sheet surface — #1A1A27
    static let surface   = Color(red: 0.102, green: 0.102, blue: 0.153)
    /// Divider / secondary surface — #26263A
    static let surface2  = Color(red: 0.149, green: 0.149, blue: 0.227)
    /// Warm amber accent — #FA9500
    static let accent    = Color(red: 0.980, green: 0.584, blue: 0.000)
    /// Accent at 15 % opacity — for pills / badges
    static let accentDim = Color(red: 0.980, green: 0.584, blue: 0.000).opacity(0.15)
    /// Favorited heart — #F53840 warm red
    static let heart     = Color(red: 0.96, green: 0.22, blue: 0.24)
}

// MARK: - Button style

struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.95
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Safe subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
