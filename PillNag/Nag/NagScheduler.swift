import Foundation
import SwiftData
import os

/// One alert in a nag chain: index 0 rings at the dose time, 1…n are follow-ups.
struct PlannedNag {
    let doseKey: String
    let medID: UUID
    let medName: String
    let medDose: String
    let colorHex: String
    let scheduledAt: Date
    let fireDate: Date
    let index: Int
    let followUps: Int
    let sound: AlarmSound

    var title: String {
        index == 0 ? "Time for \(medName)" : "Still need \(medName)"
    }

    var body: String {
        let dose = medDose.isEmpty ? "" : "\(medDose) · "
        if index == 0 { return "\(dose)scheduled for \(scheduledAt.shortTime)" }
        return "\(dose)due \(scheduledAt.shortTime) · reminder \(index) of \(followUps)"
    }
}

/// Rebuilds every pending alarm/notification from scratch. Idempotent, so it is safe to call often:
/// on launch, on foreground, after any dose action or edit, and from background refresh.
@MainActor
final class NagScheduler {
    static let shared = NagScheduler()

    /// How far ahead alerts are booked. Kept short so notification limits aren't hit.
    static let horizon: TimeInterval = 36 * 3600

    private let log = Logger(subsystem: "com.pillnag.app", category: "NagScheduler")
    private var isRunning = false
    private var needsRerun = false

    private(set) var lastScheduledCount = 0
    private(set) var lastBackend: Backend = .none

    enum Backend: String { case alarmKit = "AlarmKit", notifications = "Notifications", none = "None" }

    func requestReschedule() {
        Task { await rescheduleAll() }
    }

    func rescheduleAll() async {
        if isRunning { needsRerun = true; return }
        isRunning = true
        repeat {
            needsRerun = false
            await performReschedule()
        } while needsRerun
        isRunning = false
    }

    func plan(now: Date = .now) -> [PlannedNag] {
        let context = Persistence.context
        let meds = ((try? context.fetch(FetchDescriptor<Medication>())) ?? [])
            .filter { !$0.isArchived && $0.nagEnabled && $0.scheduleKind != .asNeeded }
        guard !meds.isEmpty else { return [] }

        let configs = Dictionary(uniqueKeysWithValues: meds.map { ($0.id, NagConfig.resolved(for: $0)) })
        let longestChain = configs.values.map(\.chainDuration).max() ?? 0
        let windowStart = now.addingTimeInterval(-longestChain - 60)
        let windowEnd = now.addingTimeInterval(Self.horizon)

        let since = windowStart.addingTimeInterval(-86_400)
        let events = (try? context.fetch(FetchDescriptor<DoseEvent>(predicate: #Predicate<DoseEvent> { $0.actionAt >= since }))) ?? []
        let byKey = DoseBoard.eventsByKey(events)

        var planned: [PlannedNag] = []
        for med in meds {
            guard let config = configs[med.id] else { continue }
            for occurrence in med.occurrences(from: windowStart, to: windowEnd) {
                let key = DoseKey.make(med.id, occurrence)
                var base = occurrence
                if let event = byKey[key] {
                    switch event.status {
                    case .taken, .skipped: continue
                    case .snoozed: base = max(occurrence, event.snoozedUntil ?? occurrence)
                    }
                }
                for index in 0...config.maxFollowUps {
                    let fire = base.addingTimeInterval(TimeInterval(index * config.intervalMinutes * 60))
                    guard fire > now.addingTimeInterval(2) else { continue }
                    planned.append(PlannedNag(doseKey: key, medID: med.id, medName: med.name, medDose: med.dose,
                                              colorHex: med.colorHex, scheduledAt: occurrence, fireDate: fire,
                                              index: index, followUps: config.maxFollowUps, sound: config.sound))
                }
            }
        }
        return planned.sorted { $0.fireDate < $1.fireDate }
    }

    private func performReschedule() async {
        let planned = plan()
        if AlarmBackend.isAuthorized {
            await NotificationBackend.removeAllPendingNags()
            let batch = Array(planned.prefix(AlarmBackend.maxScheduled))
            await AlarmBackend.replaceAll(with: batch)
            lastBackend = .alarmKit
            lastScheduledCount = batch.count
        } else {
            AlarmBackend.cancelAll()
            if await NotificationBackend.isAuthorized() {
                let batch = Array(planned.prefix(NotificationBackend.maxScheduled))
                await NotificationBackend.replaceAll(with: batch)
                lastBackend = .notifications
                lastScheduledCount = batch.count
            } else {
                lastBackend = .none
                lastScheduledCount = 0
            }
        }
        log.info("Scheduled \(self.lastScheduledCount) nags via \(self.lastBackend.rawValue)")
    }
}
