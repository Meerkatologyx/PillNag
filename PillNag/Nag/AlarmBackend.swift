import Foundation
import AlarmKit
import ActivityKit
import SwiftUI
import os

struct DoseAlarmMetadata: AlarmMetadata {
    var doseKey: String
    var medName: String
    var nagIndex: Int
}

/// AlarmKit-backed nags. Every alarm has a "Taken" stop button and a "Snooze" button,
/// both wired to App Intents that run inside the app process (no extension needed).
@MainActor
enum AlarmBackend {
    static let maxScheduled = 96
    private static let registryKey = "alarm.registry"
    private static let log = Logger(subsystem: "com.pillnag.app", category: "AlarmBackend")

    static var authorizationState: AlarmManager.AuthorizationState {
        AlarmManager.shared.authorizationState
    }

    static var isAuthorized: Bool { authorizationState == .authorized }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        do {
            return try await AlarmManager.shared.requestAuthorization() == .authorized
        } catch {
            log.error("AlarmKit authorization failed: \(error.localizedDescription)")
            return false
        }
    }

    /// alarm UUID string → doseKey, so ringing alarms can be matched to doses.
    private static var registry: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: registryKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: registryKey) }
    }

    static func replaceAll(with nags: [PlannedNag]) async {
        let manager = AlarmManager.shared
        let existing = (try? manager.alarms) ?? []
        var newRegistry: [String: String] = [:]
        let oldRegistry = registry

        // Leave anything currently ringing alone; the user's action on it (or a dose action) stops it.
        for alarm in existing {
            if alarm.state == .alerting {
                if let key = oldRegistry[alarm.id.uuidString] { newRegistry[alarm.id.uuidString] = key }
            } else {
                try? manager.cancel(id: alarm.id)
            }
        }

        let tint = Theme.storedAccentColor
        for nag in nags {
            let id = UUID()
            do {
                _ = try await manager.schedule(id: id, configuration: configuration(for: nag, tint: tint))
                newRegistry[id.uuidString] = nag.doseKey
            } catch {
                log.error("Failed to schedule alarm: \(error.localizedDescription)")
            }
        }
        registry = newRegistry
    }

    static func cancelAll() {
        let manager = AlarmManager.shared
        for alarm in (try? manager.alarms) ?? [] {
            try? manager.cancel(id: alarm.id)
        }
        registry = [:]
    }

    /// Silences any ringing alarm belonging to this dose.
    static func stopAlerting(doseKey: String) {
        let manager = AlarmManager.shared
        let map = registry
        for alarm in (try? manager.alarms) ?? [] where map[alarm.id.uuidString] == doseKey {
            if alarm.state == .alerting {
                try? manager.stop(id: alarm.id)
            } else {
                try? manager.cancel(id: alarm.id)
            }
        }
    }

    static var scheduledCount: Int { ((try? AlarmManager.shared.alarms) ?? []).count }

    private static func configuration(for nag: PlannedNag, tint: Color) -> AlarmManager.AlarmConfiguration<DoseAlarmMetadata> {
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: nag.title),
            stopButton: AlarmButton(text: "Taken", textColor: .white, systemImageName: "checkmark.circle.fill"),
            secondaryButton: AlarmButton(text: "Snooze", textColor: .white, systemImageName: "zzz"),
            secondaryButtonBehavior: .custom
        )
        let attributes = AlarmAttributes<DoseAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: DoseAlarmMetadata(doseKey: nag.doseKey, medName: nag.medName, nagIndex: nag.index),
            tintColor: tint
        )
        return AlarmManager.AlarmConfiguration<DoseAlarmMetadata>(
            countdownDuration: nil,
            schedule: .fixed(nag.fireDate),
            attributes: attributes,
            stopIntent: TakeDoseIntent(doseKey: nag.doseKey),
            secondaryIntent: SnoozeDoseIntent(doseKey: nag.doseKey),
            sound: nag.sound.alarmSound
        )
    }
}
