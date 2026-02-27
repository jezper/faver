import SwiftUI

// MARK: - Custom heart shape (Bézier — no SF Symbols dependency)

private struct HeartShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        // Two lobe circles of radius w*0.25, centered at the 25 % / 75 % marks.
        // This makes lc.x + r = 0.50·w and rc.x − r = 0.50·w, so the arcs
        // meet exactly at the centre valley — no gap, no kink.
        let r  = w * 0.25
        let lc = CGPoint(x: w * 0.25, y: h * 0.28)   // left lobe centre
        let rc = CGPoint(x: w * 0.75, y: h * 0.28)   // right lobe centre

        return Path { p in
            // ① Start at the pointed tip
            p.move(to: CGPoint(x: w * 0.5, y: h * 0.87))

            // ② Smooth curve up to the leftmost point of the left lobe
            p.addCurve(
                to: CGPoint(x: lc.x - r, y: lc.y),
                control1: CGPoint(x: w * 0.18, y: h * 0.76),
                control2: CGPoint(x: lc.x - r, y: h * 0.54)
            )

            // ③ Left lobe arc — counter-clockwise in screen coords traces over the top
            p.addArc(center: lc, radius: r,
                     startAngle: .degrees(180), endAngle: .degrees(0),
                     clockwise: false)

            // ④ Right lobe arc — same direction; starts exactly where left arc ended
            p.addArc(center: rc, radius: r,
                     startAngle: .degrees(180), endAngle: .degrees(0),
                     clockwise: false)

            // ⑤ Curve back down to the tip (mirrors step ②)
            p.addCurve(
                to: CGPoint(x: w * 0.5, y: h * 0.87),
                control1: CGPoint(x: rc.x + r, y: h * 0.54),
                control2: CGPoint(x: w * 0.82, y: h * 0.76)
            )
            p.closeSubpath()
        }
    }
}

// MARK: - Icon designs

/// Light + Dark variant — dark theme is already dark so both use the same design.
struct AppIconView: View {
    var body: some View {
        ZStack {
            // Deep navy background
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.06, blue: 0.14),
                    Color(red: 0.03, green: 0.03, blue: 0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Warm ambient glow behind the heart
            RadialGradient(
                colors: [
                    Color(red: 0.99, green: 0.62, blue: 0.06).opacity(0.22),
                    .clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 440
            )

            // Heart — amber top-left → red bottom-right
            HeartShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.99, green: 0.70, blue: 0.16),
                            Color(red: 0.97, green: 0.24, blue: 0.26)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 580, height: 620)
                .shadow(color: Color(red: 0.97, green: 0.24, blue: 0.26).opacity(0.50),
                        radius: 52, x: 0, y: 16)
                .shadow(color: Color(red: 0.99, green: 0.62, blue: 0.06).opacity(0.28),
                        radius: 88, x: 0, y: -8)
        }
        .frame(width: 1024, height: 1024)
    }
}

/// Tinted variant — monochrome heart; iOS will tint it with the user's accent colour.
struct AppIconTintedView: View {
    var body: some View {
        ZStack {
            Color(red: 0.12, green: 0.11, blue: 0.18)
            HeartShape()
                .fill(.white)
                .frame(width: 580, height: 620)
        }
        .frame(width: 1024, height: 1024)
    }
}

// MARK: - Export helper (debug only)

#if DEBUG
enum AppIconExporter {
    /// Renders all three icon variants and writes them into the Xcode asset catalog.
    /// Skips silently if the files already exist.
    @MainActor
    static func exportIfNeeded() {
        let dir = "/Users/jezper.lorne/Projects/faver/Faver/Faver/Assets.xcassets/AppIcon.appiconset/"
        let firstFile = dir + "AppIcon.png"
        guard !FileManager.default.fileExists(atPath: firstFile) else { return }

        let icons: [(AnyView, String)] = [
            (AnyView(AppIconView()),       "AppIcon"),
            (AnyView(AppIconView()),       "AppIcon-dark"),
            (AnyView(AppIconTintedView()), "AppIcon-tinted")
        ]

        for (view, name) in icons {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1.0
            guard let data = renderer.uiImage?.pngData() else {
                print("⚠️ AppIconExporter: could not render \(name)")
                continue
            }
            let url = URL(fileURLWithPath: dir + name + ".png")
            do {
                try data.write(to: url)
                print("✅ AppIconExporter: \(name).png")
            } catch {
                print("❌ AppIconExporter: \(error.localizedDescription)")
            }
        }
    }
}
#endif

// MARK: - Previews

#Preview("Light / Dark — 1024 × 1024", traits: .fixedLayout(width: 1024, height: 1024)) {
    AppIconView()
}

#Preview("Tinted — 1024 × 1024", traits: .fixedLayout(width: 1024, height: 1024)) {
    AppIconTintedView()
}
