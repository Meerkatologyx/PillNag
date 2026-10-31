import SwiftUI
import AVFoundation
import UIKit
import AudioToolbox
import AlarmKit
import UserNotifications

struct SettingsView: View {
    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(SettingsKey.appearance) private var appearanceRaw = AppearanceChoice.system.rawValue
    @AppStorage(SettingsKey.accent) private var accentRaw = AccentChoice.indigo.rawValue
    @AppStorage(SettingsKey.glassTint) private var glassTintRaw = GlassTintChoice.clear.rawValue
    @AppStorage(SettingsKey.glassStrength) private var glassStrength = 0.25
    @AppStorage(SettingsKey.nagInterval) private var nagInterval = NagDefaults.interval
    @AppStorage(SettingsKey.maxNags) private var maxNags = NagDefaults.maxNags
    @AppStorage(SettingsKey.untilTaken) private var untilTaken = NagDefaults.untilTaken
    @AppStorage(SettingsKey.snooze) private var snooze = NagDefaults.snooze
    @AppStorage(SettingsKey.sound) private var soundRaw = NagDefaults.sound

    @State private var alarmState: AlarmManager.AuthorizationState = .notDetermined
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var scheduledSummary = ""

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                glassSection
                nagSection
                alertsSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background { AppBackground() }
            .navigationTitle("Settings")
            .task { await refreshStatus() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await refreshStatus() } }
            }
            .onChange(of: nagInterval) { reschedule() }
            .onChange(of: maxNags) { reschedule() }
            .onChange(of: untilTaken) { reschedule() }
            .onChange(of: snooze) { reschedule() }
            .onChange(of: soundRaw) { reschedule() }
            .onChange(of: accentRaw) { reschedule() }
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Mode", selection: $appearanceRaw.animation(.easeInOut)) {
                ForEach(AppearanceChoice.allCases) { choice in
                    Label(choice.title, systemImage: choice.symbol).tag(choice.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)

            VStack(alignment: .leading, spacing: 10) {
                Text("Accent")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 12) {
                    ForEach(AccentChoice.allCases) { choice in
                        ColorDot(color: choice.color, selected: accentRaw == choice.rawValue) {
                            withAnimation(.snappy) { accentRaw = choice.rawValue }
                        }
                        .accessibilityLabel(choice.title)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Glass

    private var glassSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Glass tint")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 7), spacing: 10) {
                    ForEach(GlassTintChoice.allCases) { choice in
                        let color = choice.color(accent: theme.accent)
                        Button {
                            withAnimation(.snappy) { glassTintRaw = choice.rawValue }
                        } label: {
                            ZStack {
                                if color == nil {
                                    Image(systemName: "circle.slash").foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 36, height: 36)
                            .glassEffect(.regular.tint(color?.opacity(0.6)).interactive(), in: .circle)
                            .overlay {
                                if glassTintRaw == choice.rawValue {
                                    Circle().strokeBorder(Color.primary, lineWidth: 2).padding(-3)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(choice.title)
                    }
                }
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading) {
                LabeledContent("Tint strength", value: "\(Int(glassStrength * 100))%")
                Slider(value: $glassStrength, in: 0...0.6)
            }
            .disabled(glassTintRaw == GlassTintChoice.clear.rawValue)

            GlassPreview()
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
        } header: {
            Text("Liquid Glass")
        }
    }

    // MARK: Nagging

    private var nagSection: some View {
        Section {
            Stepper(value: $nagInterval, in: 1...60) {
                LabeledContent("Nag every", value: "\(nagInterval) min")
            }
            Toggle(isOn: $untilTaken.animation(.snappy)) {
                Label("Nag until taken", systemImage: "infinity")
            }
            if !untilTaken {
                Stepper(value: $maxNags, in: 0...20) {
                    LabeledContent("Follow-up nags", value: "\(maxNags)")
                }
            }
            Stepper(value: $snooze, in: 1...120) {
                LabeledContent("Snooze length", value: "\(snooze) min")
            }
            Picker("Alarm sound", selection: $soundRaw) {
                ForEach(AlarmSound.allCases) { sound in
                    Text(sound.title).tag(sound.rawValue)
                }
            }
            Button {
                SoundPreviewer.shared.play(AlarmSound(rawValue: soundRaw) ?? .chime)
            } label: {
                Label("Preview sound", systemImage: "speaker.wave.2.fill")
            }
        } header: {
            Text("Nagging")
        } footer: {
            Text(nagFooter)
        }
    }

    // MARK: Alerts

    private var alertsSection: some View {
        Section {
            StatusRow(title: "Alarms (AlarmKit)", symbol: "alarm.fill", status: alarmStatusText, ok: alarmState == .authorized)
            if alarmState == .notDetermined {
                Button("Allow Alarms") {
                    Task { await AlarmBackend.requestAuthorization(); await refreshStatus(); reschedule() }
                }
            }
            StatusRow(title: "Notifications", symbol: "bell.badge.fill", status: notificationStatusText,
                      ok: notificationStatus == .authorized)
            if notificationStatus == .notDetermined {
                Button("Allow Notifications") {
                    Task { await NotificationBackend.requestAuthorization(); await refreshStatus(); reschedule() }
                }
            }
            if alarmState == .denied || notificationStatus == .denied {
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
            Button {
                Task {
                    await NagScheduler.shared.rescheduleAll()
                    await refreshStatus()
                }
            } label: {
                LabeledContent {
                    Text(scheduledSummary).contentTransition(.numericText())
                } label: {
                    Label("Reschedule now", systemImage: "arrow.clockwise")
                }
            }
        } header: {
            Text("Alerts")
        } footer: {
            Text("Alarms ring even in Silent mode and Focus. Stopping an alarm only silences it — doses are marked taken in the app. If alarms aren't allowed, PillNag falls back to notifications with a Snooze button.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: appVersion)
            LabeledContent("Data", value: "Stored only on this iPhone")
        }
    }

    // MARK: Helpers

    private var nagFooter: String {
        if untilTaken {
            return "PillNag rings every \(nagInterval) min until you mark the dose taken (or skip it) in the app, or until that med's next dose is due. Individual meds can override this."
        }
        if maxNags == 0 { return "Rings once at dose time." }
        return "Until you mark the dose taken in the app, PillNag rings again every \(nagInterval) min, up to \(maxNags) more times (\(nagInterval * maxNags) min). Individual meds can override this."
    }

    private var alarmStatusText: String {
        switch alarmState {
        case .authorized: "Allowed"
        case .denied: "Denied"
        case .notDetermined: "Not set"
        @unknown default: "Unknown"
        }
    }

    private var notificationStatusText: String {
        switch notificationStatus {
        case .authorized: "Allowed"
        case .denied: "Denied"
        case .provisional, .ephemeral: "Quiet"
        case .notDetermined: "Not set"
        @unknown default: "Unknown"
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private func reschedule() {
        NagScheduler.shared.requestReschedule()
        Task {
            try? await Task.sleep(for: .seconds(1))
            await refreshStatus()
        }
    }

    private func refreshStatus() async {
        alarmState = AlarmBackend.authorizationState
        notificationStatus = await NotificationBackend.authorizationStatus()
        let scheduler = NagScheduler.shared
        withAnimation {
            scheduledSummary = "\(scheduler.lastScheduledCount) via \(scheduler.lastBackend.rawValue)"
        }
    }
}

private struct ColorDot: View {
    let color: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color.gradient)
                .frame(width: 38, height: 38)
                .overlay {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.footnote.bold())
                            .foregroundStyle(.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(3)
                .overlay(Circle().strokeBorder(selected ? color : .clear, lineWidth: 2))
                .scaleEffect(selected ? 1.06 : 1)
        }
        .buttonStyle(.plain)
    }
}

private struct StatusRow: View {
    let title: String
    let symbol: String
    let status: String
    let ok: Bool

    var body: some View {
        LabeledContent {
            Label(status, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(ok ? Color.green : Color.orange)
        } label: {
            Label(title, systemImage: symbol)
        }
    }
}

/// Live sample of the current glass settings.
private struct GlassPreview: View {
    @Environment(\.theme) private var theme
    @Namespace private var ns
    @State private var expanded = false

    var body: some View {
        ZStack {
            AppBackground()
                .clipShape(.rect(cornerRadius: 24))
            GlassEffectContainer(spacing: 16) {
                HStack(spacing: 16) {
                    Image(systemName: "pills.fill")
                        .font(.title2)
                        .frame(width: 56, height: 56)
                        .glassEffect(theme.glass(interactive: true), in: .circle)
                        .glassEffectID("pill", in: ns)
                    if expanded {
                        Text("Liquid Glass")
                            .font(.headline)
                            .padding(.horizontal, 18)
                            .frame(height: 56)
                            .glassEffect(theme.glass(interactive: true), in: .capsule)
                            .glassEffectID("label", in: ns)
                    }
                }
            }
            .onTapGesture {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { expanded.toggle() }
            }
        }
        .frame(height: 120)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.3)) { expanded = true }
        }
    }
}

@MainActor
final class SoundPreviewer {
    static let shared = SoundPreviewer()
    private var player: AVAudioPlayer?

    func play(_ sound: AlarmSound) {
        guard let file = sound.fileName, let url = Bundle.main.url(forResource: file, withExtension: nil) else {
            AudioServicesPlaySystemSound(1005)
            return
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}
