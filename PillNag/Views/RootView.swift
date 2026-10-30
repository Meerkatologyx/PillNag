import SwiftUI

enum AppTab: Hashable {
    case today, meds, history, settings
}

struct RootView: View {
    @AppStorage(SettingsKey.accent) private var accentRaw = AccentChoice.indigo.rawValue
    @AppStorage(SettingsKey.glassTint) private var glassTintRaw = GlassTintChoice.clear.rawValue
    @AppStorage(SettingsKey.glassStrength) private var glassStrength = 0.25
    @AppStorage(SettingsKey.appearance) private var appearanceRaw = AppearanceChoice.system.rawValue
    @AppStorage(SettingsKey.onboarded) private var onboarded = false

    @State private var tab: AppTab = .today
    @State private var showWelcome = false

    private var theme: Theme {
        let accent = (AccentChoice(rawValue: accentRaw) ?? .indigo).color
        let tint = (GlassTintChoice(rawValue: glassTintRaw) ?? .clear).color(accent: accent)
        return Theme(accent: accent, glassTint: tint, glassStrength: glassStrength)
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Today", systemImage: "sun.max.fill", value: AppTab.today) {
                TodayView()
            }
            Tab("Meds", systemImage: "pills.fill", value: AppTab.meds) {
                MedsView()
            }
            Tab("History", systemImage: "chart.bar.xaxis", value: AppTab.history) {
                HistoryView()
            }
            Tab("Settings", systemImage: "slider.horizontal.3", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(theme.accent)
        .environment(\.theme, theme)
        .preferredColorScheme((AppearanceChoice(rawValue: appearanceRaw) ?? .system).colorScheme)
        .sheet(isPresented: $showWelcome) {
            WelcomeView { onboarded = true }
                .environment(\.theme, theme)
                .tint(theme.accent)
                .interactiveDismissDisabled()
        }
        .task {
            if !onboarded { showWelcome = true }
            NagScheduler.shared.requestReschedule()
        }
    }
}
