import SwiftUI

struct CardGlass: ViewModifier {
    @Environment(\.theme) private var theme
    var cornerRadius: CGFloat
    var tint: Color?
    var interactive: Bool

    func body(content: Content) -> some View {
        content.glassEffect(theme.glass(tint: tint, interactive: interactive), in: .rect(cornerRadius: cornerRadius))
    }
}

struct CapsuleGlass: ViewModifier {
    @Environment(\.theme) private var theme
    var tint: Color?
    var interactive: Bool

    func body(content: Content) -> some View {
        content.glassEffect(theme.glass(tint: tint, interactive: interactive), in: .capsule)
    }
}

extension View {
    /// Rounded-rect Liquid Glass card using the app theme.
    func cardGlass(cornerRadius: CGFloat = 26, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(CardGlass(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }

    /// Capsule Liquid Glass using the app theme.
    func capsuleGlass(tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(CapsuleGlass(tint: tint, interactive: interactive))
    }
}

/// Soft, slowly drifting mesh gradient behind every screen so the glass has something to refract.
struct AppBackground: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: reduceMotion)) { context in
            let t = Float(context.date.timeIntervalSinceReferenceDate)
            let drift = SIMD2<Float>(0.5 + 0.12 * sin(t / 7), 0.5 + 0.1 * cos(t / 9))
            let base: Color = scheme == .dark ? Color(hex: "#0B0D17") : Color(hex: "#F4F5FB")
            let accentWash = theme.accent.opacity(scheme == .dark ? 0.45 : 0.30)
            let second = (theme.glassTint ?? Color(hex: "#30B0C7")).opacity(scheme == .dark ? 0.35 : 0.25)
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], drift, [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: [
                    accentWash, base, second,
                    base, accentWash.opacity(0.6), base,
                    second, base, accentWash,
                ]
            )
            .background(base)
        }
        .ignoresSafeArea()
    }
}
