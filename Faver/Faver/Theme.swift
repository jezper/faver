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
        PressScale(configuration: configuration, scale: scale)
    }

    /// A ButtonStyle cannot read the environment directly, so the body lives in a real
    /// view. Someone who has asked the system to reduce motion still gets the press
    /// feedback, it just stops springing.
    private struct PressScale: View {
        let configuration: Configuration
        let scale: CGFloat
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? scale : 1)
                .animation(
                    reduceMotion ? .linear(duration: 0.1)
                                 : .spring(response: 0.25, dampingFraction: 0.7),
                    value: configuration.isPressed
                )
        }
    }
}

// MARK: - Motion

extension Animation {
    /// A spring that flattens to a plain fade when the system asks for reduced motion.
    static func calm(reduceMotion: Bool, response: Double = 0.3, damping: Double = 0.7) -> Animation {
        reduceMotion
            ? .linear(duration: 0.15)
            : .spring(response: response, dampingFraction: damping)
    }
}

// MARK: - Safe subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
