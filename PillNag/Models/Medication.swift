import Foundation
import SwiftData
import SwiftUI

@Model
final class Medication {
    var id: UUID = UUID()
    var name: String = ""
    var dose: String = ""
    var shapeRaw: String = "capsule"
    var colorHex: String = "#FF5E78"
    var secondaryColorHex: String = "#FAFAFF"
    var symbol: String = "pills.fill"
    var useSymbol: Bool = false
    var notes: String = ""
    var createdAt: Date = Date()
    var isArchived: Bool = false
    var sortOrder: Int = 0

    // Supply
    var tracksSupply: Bool = true
    var pillsRemaining: Int = 30
    var pillsPerDose: Int = 1
    var lowSupplyThreshold: Int = 7

    // Schedule
    var scheduleKindRaw: String = "daily"
    /// Minutes after midnight, used by `.daily` and `.weekdays`.
    var timesOfDay: [Int] = [480]
    /// Calendar weekday numbers (1 = Sunday … 7 = Saturday), used by `.weekdays`.
    var weekdays: [Int] = [2, 3, 4, 5, 6]
    var intervalHours: Int = 8
    /// First dose of the day for `.interval`, minutes after midnight.
    var intervalAnchorMinutes: Int = 480
    /// Doses before this moment are never considered due or missed.
    var scheduleStart: Date = Date()

    // Nagging (nil = use the global default)
    var nagEnabled: Bool = true
    var nagIntervalOverride: Int?
    var maxNagsOverride: Int?
    var nagUntilTakenOverride: Bool?
    var snoozeOverride: Int?
    var soundOverride: String?

    @Relationship(deleteRule: .nullify, inverse: \DoseEvent.medication)
    var events: [DoseEvent]? = []

    init(name: String = "", dose: String = "") {
        self.id = UUID()
        self.name = name
        self.dose = dose
        self.createdAt = Date()
        self.scheduleStart = Date()
    }

    var shape: PillShape {
        get { PillShape(rawValue: shapeRaw) ?? .capsule }
        set { shapeRaw = newValue.rawValue }
    }

    var scheduleKind: ScheduleKind {
        get { ScheduleKind(rawValue: scheduleKindRaw) ?? .daily }
        set { scheduleKindRaw = newValue.rawValue }
    }

    var color: Color { Color(hex: colorHex) }
    var secondaryColor: Color { Color(hex: secondaryColorHex) }

    var isLowSupply: Bool { tracksSupply && pillsRemaining <= lowSupplyThreshold }

    /// Days of supply left at the current schedule, if it can be estimated.
    var daysOfSupplyLeft: Int? {
        guard tracksSupply, pillsPerDose > 0 else { return nil }
        let perDay: Double
        switch scheduleKind {
        case .daily: perDay = Double(timesOfDay.count)
        case .weekdays: perDay = Double(timesOfDay.count * weekdays.count) / 7
        case .interval: perDay = 24 / Double(max(1, intervalHours))
        case .asNeeded: return nil
        }
        guard perDay > 0 else { return nil }
        return Int(Double(pillsRemaining) / (perDay * Double(pillsPerDose)))
    }

    var scheduleSummary: String {
        let times = timesOfDay.sorted().map { Date.atMinutes($0).formatted(date: .omitted, time: .shortened) }
        switch scheduleKind {
        case .daily:
            return times.isEmpty ? "Daily" : "Daily at " + times.joined(separator: ", ")
        case .weekdays:
            let symbols = Calendar.current.shortWeekdaySymbols
            let days = weekdays.sorted().map { symbols[($0 - 1) % 7] }.joined(separator: " ")
            return "\(days) at " + times.joined(separator: ", ")
        case .interval:
            let start = Date.atMinutes(intervalAnchorMinutes).formatted(date: .omitted, time: .shortened)
            return "Every \(intervalHours)h from \(start)"
        case .asNeeded:
            return "As needed"
        }
    }

    /// All scheduled dose times in `[start, end)`.
    func occurrences(from start: Date, to end: Date, calendar: Calendar = .current) -> [Date] {
        let effectiveStart = max(start, scheduleStart)
        guard effectiveStart < end else { return [] }

        switch scheduleKind {
        case .asNeeded:
            return []

        case .daily, .weekdays:
            let allowed = Set(weekdays)
            let times = timesOfDay.sorted()
            var result: [Date] = []
            var day = calendar.startOfDay(for: effectiveStart)
            while day < end {
                let weekday = calendar.component(.weekday, from: day)
                if scheduleKind == .daily || allowed.contains(weekday) {
                    for minutes in times {
                        if let date = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day),
                           date >= effectiveStart, date < end {
                            result.append(date)
                        }
                    }
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
            return result

        case .interval:
            let step = TimeInterval(max(1, intervalHours) * 3600)
            let anchorDay = calendar.startOfDay(for: scheduleStart)
            guard let anchor = calendar.date(bySettingHour: intervalAnchorMinutes / 60,
                                             minute: intervalAnchorMinutes % 60, second: 0, of: anchorDay)
            else { return [] }
            var k = Int(floor(effectiveStart.timeIntervalSince(anchor) / step))
            var result: [Date] = []
            while true {
                let date = anchor.addingTimeInterval(Double(k) * step)
                if date >= end { break }
                if date >= effectiveStart { result.append(date) }
                k += 1
            }
            return result
        }
    }
}
