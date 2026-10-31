import Foundation

/// What a single dose looks like right now.
enum DoseState: Equatable {
    case upcoming
    case due
    case overdue
    case snoozed(until: Date)
    case taken(at: Date)
    case skipped
    case missed

    var isResolved: Bool {
        switch self {
        case .taken, .skipped, .missed: true
        default: false
        }
    }

    var isActionable: Bool {
        switch self {
        case .upcoming, .due, .overdue, .snoozed: true
        default: false
        }
    }

    var sortRank: Int {
        switch self {
        case .overdue: 0
        case .due: 1
        case .snoozed: 2
        case .upcoming: 3
        case .taken: 4
        case .skipped: 5
        case .missed: 6
        }
    }
}

struct DoseItem: Identifiable {
    let id: String
    let medication: Medication?
    let medID: UUID
    let medName: String
    let medDose: String
    let colorHex: String
    /// nil for as-needed doses.
    let scheduledAt: Date?
    let event: DoseEvent?
    let state: DoseState

    /// The time shown for the dose.
    var displayTime: Date { scheduledAt ?? event?.actionAt ?? .now }

    func with(state: DoseState) -> DoseItem {
        DoseItem(id: id, medication: medication, medID: medID, medName: medName, medDose: medDose,
                 colorHex: colorHex, scheduledAt: scheduledAt, event: event, state: state)
    }
}

/// Pure functions that turn meds + events into dose items, streaks and adherence.
enum DoseBoard {
    /// A dose counts as "due" (rather than overdue) for this long after its time.
    static let dueWindow: TimeInterval = 30 * 60

    static func eventsByKey(_ events: [DoseEvent]) -> [String: DoseEvent] {
        var dict: [String: DoseEvent] = [:]
        for event in events where !event.doseKey.isEmpty {
            dict[event.doseKey] = event
        }
        return dict
    }

    static func state(scheduledAt: Date, event: DoseEvent?, now: Date, calendar: Calendar = .current) -> DoseState {
        if let event {
            switch event.status {
            case .taken: return .taken(at: event.actionAt)
            case .skipped: return .skipped
            case .snoozed:
                if let until = event.snoozedUntil, until > now { return .snoozed(until: until) }
            }
        }
        if scheduledAt > now { return .upcoming }
        if scheduledAt < calendar.startOfDay(for: now) { return .missed }
        return now.timeIntervalSince(scheduledAt) <= dueWindow ? .due : .overdue
    }

    /// Every dose for the calendar day containing `day`, including as-needed doses taken that day.
    static func items(on day: Date, meds: [Medication], events: [DoseEvent], now: Date = .now,
                      calendar: Calendar = .current) -> [DoseItem] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let byKey = eventsByKey(events)
        var seen = Set<String>()
        var items: [DoseItem] = []

        for med in meds where !med.isArchived {
            for date in med.occurrences(from: start, to: end, calendar: calendar) {
                let key = DoseKey.make(med.id, date)
                let event = byKey[key]
                seen.insert(key)
                items.append(DoseItem(id: key, medication: med, medID: med.id, medName: med.name, medDose: med.dose,
                                      colorHex: med.colorHex, scheduledAt: date, event: event,
                                      state: state(scheduledAt: date, event: event, now: now, calendar: calendar)))
            }
        }

        // Events that don't match the current schedule: as-needed doses, or doses from an older schedule.
        for event in events where !seen.contains(event.doseKey) {
            let anchor = event.scheduledAt ?? event.actionAt
            guard anchor >= start, anchor < end, event.status != .snoozed else { continue }
            seen.insert(event.doseKey)
            let state: DoseState = event.status == .taken ? .taken(at: event.actionAt) : .skipped
            items.append(DoseItem(id: event.doseKey, medication: event.medication, medID: event.medID,
                                  medName: event.medication?.name ?? event.medName,
                                  medDose: event.medication?.dose ?? event.medDose,
                                  colorHex: event.medication?.colorHex ?? event.medColorHex,
                                  scheduledAt: event.scheduledAt, event: event, state: state))
        }

        return items.sorted { $0.displayTime < $1.displayTime }
    }

    /// Yesterday's doses that are still being nagged about (e.g. an evening dose past midnight),
    /// surfaced on Today as overdue so they can still be marked taken.
    static func carryOver(meds: [Medication], events: [DoseEvent], now: Date = .now,
                          calendar: Calendar = .current) -> [DoseItem] {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return [] }
        return items(on: yesterday, meds: meds, events: events, now: now, calendar: calendar).compactMap { item in
            guard let med = item.medication, med.nagEnabled, let at = item.scheduledAt else { return nil }
            switch item.state {
            case .snoozed:
                return item
            case .missed:
                let end = NagConfig.resolved(for: med).nagEnd(for: med, occurrence: at)
                return end > now ? item.with(state: .overdue) : nil
            default:
                return nil
            }
        }
    }

    struct DaySummary: Identifiable {
        let day: Date
        let scheduled: Int
        let taken: Int
        let skipped: Int
        var id: Date { day }
        var adherence: Double? { scheduled == 0 ? nil : Double(taken) / Double(scheduled) }
        /// A "perfect" day: everything scheduled was taken (skips are forgiven).
        var isComplete: Bool { scheduled > 0 && taken + skipped >= scheduled }
    }

    /// Summary for a day, counting only scheduled doses whose time has passed (or that were already handled).
    static func summary(for day: Date, meds: [Medication], byKey: [String: DoseEvent], now: Date,
                        calendar: Calendar = .current) -> DaySummary {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        var scheduled = 0, taken = 0, skipped = 0
        for med in meds where !med.isArchived {
            for date in med.occurrences(from: start, to: end, calendar: calendar) {
                let event = byKey[DoseKey.make(med.id, date)]
                let handled = event.map { $0.status != .snoozed } ?? false
                guard date <= now || handled else { continue }
                scheduled += 1
                if event?.status == .taken { taken += 1 }
                if event?.status == .skipped { skipped += 1 }
            }
        }
        return DaySummary(day: start, scheduled: scheduled, taken: taken, skipped: skipped)
    }

    static func summaries(days: Int, meds: [Medication], events: [DoseEvent], now: Date = .now,
                          calendar: Calendar = .current) -> [DaySummary] {
        let byKey = eventsByKey(events)
        let today = calendar.startOfDay(for: now)
        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return summary(for: day, meds: meds, byKey: byKey, now: now, calendar: calendar)
        }
    }

    struct Streaks {
        var current: Int
        var best: Int
    }

    /// Consecutive complete days. Days with nothing scheduled neither extend nor break a streak.
    /// Today counts once it is complete, but an unfinished today never breaks the streak.
    static func streaks(meds: [Medication], events: [DoseEvent], now: Date = .now,
                        calendar: Calendar = .current, lookbackDays: Int = 365) -> Streaks {
        let active = meds.filter { !$0.isArchived }
        guard let earliest = active.map(\.scheduleStart).min() else { return Streaks(current: 0, best: 0) }
        let byKey = eventsByKey(events)
        let today = calendar.startOfDay(for: now)
        let firstDay = max(calendar.startOfDay(for: earliest),
                           calendar.date(byAdding: .day, value: -lookbackDays, to: today) ?? today)

        var current = 0, best = 0, run = 0
        var currentLocked = false
        var day = today
        var isToday = true
        while day >= firstDay {
            let s = summary(for: day, meds: active, byKey: byKey, now: now, calendar: calendar)
            if s.scheduled > 0 {
                if s.isComplete {
                    run += 1
                } else if !isToday {
                    if !currentLocked { current = run; currentLocked = true }
                    best = max(best, run)
                    run = 0
                }
            }
            isToday = false
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        if !currentLocked { current = run }
        best = max(best, run, current)
        return Streaks(current: current, best: best)
    }
}
