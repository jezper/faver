import SwiftUI

// MARK: - Colours

extension Color {
    /// Near-black background — #080810
    static let bg        = Color(red: 0.032, green: 0.032, blue: 0.040)
    /// Card / sheet surface — #171719
    static let surface   = Color(red: 0.090, green: 0.090, blue: 0.100)
    /// Divider / secondary surface — #232328
    static let surface2  = Color(red: 0.137, green: 0.137, blue: 0.157)
    /// Warm amber accent — #FA9500
    static let accent    = Color(red: 0.980, green: 0.584, blue: 0.000)
    /// Accent at 15 % opacity — for pills / badges
    static let accentDim = Color(red: 0.980, green: 0.584, blue: 0.000).opacity(0.15)
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
