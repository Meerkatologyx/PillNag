import SwiftUI

enum AccentChoice: String, CaseIterable, Identifiable {
    case indigo, blue, teal, mint, green, orange, pink, red, purple, graphite

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .indigo: Color(hex: "#5E6BE6")
        case .blue: Color(hex: "#0A84FF")
        case .teal: Color(hex: "#30B0C7")
        case .mint: Color(hex: "#00C7BE")
        case .green: Color(hex: "#34C759")
        case .orange: Color(hex: "#FF9500")
        case .pink: Color(hex: "#FF4F8B")
        case .red: Color(hex: "#FF3B30")
        case .purple: Color(hex: "#AF52DE")
        case .graphite: Color(hex: "#8E8E93")
        }
    }
}

enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum GlassTintChoice: String, CaseIterable, Identifiable {
    case clear, accent, blue, purple, pink, mint, amber

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    func color(accent: Color) -> Color? {
        switch self {
        case .clear: nil
        case .accent: accent
        case .blue: Color(hex: "#4DA3FF")
        case .purple: Color(hex: "#9B7BFF")
        case .pink: Color(hex: "#FF7AB6")
        case .mint: Color(hex: "#4FE0C8")
        case .amber: Color(hex: "#FFC14D")
        }
    }
}

struct Theme {
    var accent: Color
    var glassTint: Color?
    var glassStrength: Double

    static let `default` = Theme(accent: AccentChoice.indigo.color, glassTint: nil, glassStrength: 0.25)

    static var storedAccentColor: Color {
        (AccentChoice(rawValue: UserDefaults.standard.string(forKey: SettingsKey.accent) ?? "") ?? .indigo).color
    }

    /// The app's standard glass, optionally tinted (per-call tint wins over the theme tint).
    func glass(tint: Color? = nil, interactive: Bool = false) -> Glass {
        var glass = Glass.regular
        if let tint {
            glass = glass.tint(tint.opacity(0.35 + glassStrength * 0.4))
        } else if let glassTint {
            glass = glass.tint(glassTint.opacity(glassStrength))
        }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

extension EnvironmentValues {
    @Entry var theme: Theme = .default
}
