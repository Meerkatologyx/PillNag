import Foundation
import ActivityKit
import UserNotifications

enum SettingsKey {
    static let nagInterval = "nag.intervalMinutes"
    static let maxNags = "nag.maxFollowUps"
    static let snooze = "nag.snoozeMinutes"
    static let sound = "nag.sound"
    static let accent = "theme.accent"
    static let glassTint = "theme.glassTint"
    static let glassStrength = "theme.glassStrength"
    static let appearance = "theme.appearance"
    static let onboarded = "app.onboarded"
}

enum NagDefaults {
    static let interval = 5
    static let maxNags = 6
    static let snooze = 10
    static let sound = AlarmSound.chime.rawValue
}

enum AlarmSound: String, CaseIterable, Identifiable {
    case system, chime, pulse, rise, gentle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System Default"
        case .chime: "Chime"
        case .pulse: "Pulse"
        case .rise: "Rise"
        case .gentle: "Gentle"
        }
    }

    var fileName: String? { self == .system ? nil : "\(rawValue).wav" }

    var alarmSound: AlertConfiguration.AlertSound {
        guard let fileName else { return .default }
        return .named(fileName)
    }

    var notificationSound: UNNotificationSound {
        guard let fileName else { return .default }
        return UNNotificationSound(named: UNNotificationSoundName(fileName))
    }
}

/// The effective nag configuration for a medication (global defaults + per-med overrides).
struct NagConfig {
    var intervalMinutes: Int
    var maxFollowUps: Int
    var snoozeMinutes: Int
    var sound: AlarmSound

    static var global: NagConfig {
        let d = UserDefaults.standard
        return NagConfig(
            intervalMinutes: d.object(forKey: SettingsKey.nagInterval) as? Int ?? NagDefaults.interval,
            maxFollowUps: d.object(forKey: SettingsKey.maxNags) as? Int ?? NagDefaults.maxNags,
            snoozeMinutes: d.object(forKey: SettingsKey.snooze) as? Int ?? NagDefaults.snooze,
            sound: AlarmSound(rawValue: d.string(forKey: SettingsKey.sound) ?? "") ?? .chime
        )
    }

    static func resolved(for med: Medication?) -> NagConfig {
        var config = global
        guard let med else { return config }
        if let v = med.nagIntervalOverride { config.intervalMinutes = v }
        if let v = med.maxNagsOverride { config.maxFollowUps = v }
        if let v = med.snoozeOverride { config.snoozeMinutes = v }
        if let v = med.soundOverride, let s = AlarmSound(rawValue: v) { config.sound = s }
        config.intervalMinutes = max(1, config.intervalMinutes)
        config.maxFollowUps = max(0, config.maxFollowUps)
        config.snoozeMinutes = max(1, config.snoozeMinutes)
        return config
    }

    /// How long a full nag chain lasts.
    var chainDuration: TimeInterval { TimeInterval(intervalMinutes * maxFollowUps * 60) }
}
