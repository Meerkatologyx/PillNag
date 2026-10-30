import Foundation
import SwiftData

/// Every way a dose can change state goes through here, so the nag chain is always rescheduled.
@MainActor
enum DoseActions {
    enum Action { case taken, snoozed, skipped }

    /// From an alarm button, notification action, or App Intent.
    static func handleExternal(_ action: Action, doseKey: String) async {
        guard let parsed = DoseKey.parse(doseKey), let med = Persistence.medication(id: parsed.medID) else { return }
        switch action {
        case .taken: markTaken(med, scheduledAt: parsed.scheduledAt)
        case .snoozed: snooze(med, scheduledAt: parsed.scheduledAt)
        case .skipped: skip(med, scheduledAt: parsed.scheduledAt)
        }
        await NagScheduler.shared.rescheduleAll()
    }

    static func markTaken(_ med: Medication, scheduledAt: Date?, at date: Date = .now) {
        let context = Persistence.context
        let event: DoseEvent
        if let scheduledAt, let existing = Persistence.event(doseKey: DoseKey.make(med.id, scheduledAt)) {
            event = existing
        } else {
            event = DoseEvent(medication: med, scheduledAt: scheduledAt, status: .taken, at: date)
            context.insert(event)
        }
        let wasTaken = event.status == .taken && event.pillsDeducted > 0
        event.status = .taken
        event.actionAt = date
        event.snoozedUntil = nil

        if med.tracksSupply && !wasTaken {
            let before = med.pillsRemaining
            let deduct = min(med.pillsPerDose, med.pillsRemaining)
            med.pillsRemaining -= deduct
            event.pillsDeducted = deduct
            if before > med.lowSupplyThreshold && med.pillsRemaining <= med.lowSupplyThreshold {
                NotificationBackend.postLowSupply(for: med)
            }
        }
        finish(doseKey: event.doseKey)
    }

    static func snooze(_ med: Medication, scheduledAt: Date, minutes: Int? = nil) {
        let context = Persistence.context
        let key = DoseKey.make(med.id, scheduledAt)
        let event = Persistence.event(doseKey: key) ?? {
            let e = DoseEvent(medication: med, scheduledAt: scheduledAt, status: .snoozed)
            context.insert(e)
            return e
        }()
        let length = minutes ?? NagConfig.resolved(for: med).snoozeMinutes
        event.status = .snoozed
        event.actionAt = .now
        event.snoozedUntil = Date.now.addingTimeInterval(TimeInterval(length * 60))
        event.snoozeCount += 1
        finish(doseKey: key)
    }

    static func skip(_ med: Medication, scheduledAt: Date) {
        let context = Persistence.context
        let key = DoseKey.make(med.id, scheduledAt)
        let event = Persistence.event(doseKey: key) ?? {
            let e = DoseEvent(medication: med, scheduledAt: scheduledAt, status: .skipped)
            context.insert(e)
            return e
        }()
        restoreSupply(for: event)
        event.status = .skipped
        event.actionAt = .now
        event.snoozedUntil = nil
        finish(doseKey: key)
    }

    /// Removes the event entirely, putting the dose back to its scheduled state.
    static func undo(_ event: DoseEvent) {
        let key = event.doseKey
        restoreSupply(for: event)
        Persistence.context.delete(event)
        finish(doseKey: key)
    }

    static func refill(_ med: Medication, adding count: Int) {
        med.pillsRemaining = max(0, med.pillsRemaining + count)
        try? Persistence.context.save()
    }

    private static func restoreSupply(for event: DoseEvent) {
        if event.pillsDeducted > 0, let med = event.medication {
            med.pillsRemaining += event.pillsDeducted
        }
        event.pillsDeducted = 0
    }

    private static func finish(doseKey: String) {
        try? Persistence.context.save()
        AlarmBackend.stopAlerting(doseKey: doseKey)
        NotificationBackend.removeDelivered(doseKey: doseKey)
        NagScheduler.shared.requestReschedule()
    }
}
