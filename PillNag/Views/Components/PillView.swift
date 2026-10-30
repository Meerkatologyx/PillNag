import SwiftUI

/// Draws a medication as a pill shape, or as its SF Symbol.
struct PillView: View {
    var shape: PillShape
    var color: Color
    var secondary: Color
    var symbol: String?
    var size: CGFloat = 44

    init(shape: PillShape, color: Color, secondary: Color, symbol: String? = nil, size: CGFloat = 44) {
        self.shape = shape
        self.color = color
        self.secondary = secondary
        self.symbol = symbol
        self.size = size
    }

    init(med: Medication, size: CGFloat = 44) {
        self.init(shape: med.shape, color: med.color, secondary: med.secondaryColor,
                  symbol: med.useSymbol ? med.symbol : nil, size: size)
    }

    var body: some View {
        ZStack {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(color.gradient)
                    .symbolRenderingMode(.hierarchical)
            } else {
                pill
                    .shadow(color: color.opacity(0.45), radius: size * 0.08, y: size * 0.04)
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var pill: some View {
        switch shape {
        case .round:
            Circle()
                .fill(color.gradient)
                .overlay(Rectangle().fill(.black.opacity(0.12)).frame(height: size * 0.04))
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                .frame(width: size * 0.78, height: size * 0.78)
        case .capsule:
            HStack(spacing: 0) {
                Rectangle().fill(secondary.gradient)
                Rectangle().fill(color.gradient)
            }
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 1))
            .frame(width: size * 0.95, height: size * 0.42)
            .rotationEffect(.degrees(-35))
        case .oval:
            Ellipse()
                .fill(color.gradient)
                .overlay(Ellipse().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                .frame(width: size * 0.9, height: size * 0.6)
                .rotationEffect(.degrees(-20))
        case .oblong:
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .fill(color.gradient)
                .overlay(Rectangle().fill(.black.opacity(0.12)).frame(width: size * 0.04))
                .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
                .frame(width: size * 0.95, height: size * 0.48)
                .rotationEffect(.degrees(-20))
        case .diamond:
            RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                .fill(color.gradient)
                .frame(width: size * 0.58, height: size * 0.58)
                .rotationEffect(.degrees(45))
        case .triangle:
            RoundedTriangle(radius: size * 0.08)
                .fill(color.gradient)
                .frame(width: size * 0.8, height: size * 0.7)
        }
    }
}

struct RoundedTriangle: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let top = CGPoint(x: rect.midX, y: rect.minY)
        let right = CGPoint(x: rect.maxX, y: rect.maxY)
        let left = CGPoint(x: rect.minX, y: rect.maxY)
        var path = Path()
        path.move(to: CGPoint(x: (top.x + left.x) / 2, y: (top.y + left.y) / 2))
        path.addArc(tangent1End: top, tangent2End: right, radius: radius)
        path.addArc(tangent1End: right, tangent2End: left, radius: radius)
        path.addArc(tangent1End: left, tangent2End: top, radius: radius)
        path.closeSubpath()
        return path
    }
}

/// A pill sitting in a small glass puck.
struct MedBadge: View {
    let med: Medication
    var size: CGFloat = 52

    var body: some View {
        PillView(med: med, size: size * 0.78)
            .frame(width: size, height: size)
            .glassEffect(.regular.tint(med.color.opacity(0.18)), in: .circle)
    }
}
