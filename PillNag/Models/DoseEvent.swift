import Foundation
import SwiftData

/// Something the user did with a dose: took it, skipped it, or snoozed it.
/// Missed doses are not stored — they are inferred from the schedule.
@Model
final class DoseEvent {
    var id: UUID = UUID()
    var medID: UUID = UUID()
    var medName: String = ""
    var medDose: String = ""
    var medColorHex: String = "#FF5E78"
    /// `DoseKey` for scheduled doses; a unique key for as-needed doses.
    var doseKey: String = ""
    /// nil for as-needed doses.
    var scheduledAt: Date?
    var actionAt: Date = Date()
    var statusRaw: String = "taken"
    var snoozedUntil: Date?
    var snoozeCount: Int = 0
    var pillsDeducted: Int = 0

    var medication: Medication?

    init(medication: Medication, scheduledAt: Date?, status: DoseStatus, at date: Date = .now) {
        self.id = UUID()
        self.medID = medication.id
        self.medName = medication.name
        self.medDose = medication.dose
        self.medColorHex = medication.colorHex
        self.scheduledAt = scheduledAt
        self.doseKey = scheduledAt.map { DoseKey.make(medication.id, $0) } ?? "\(medication.id.uuidString)|prn|\(UUID().uuidString)"
        self.actionAt = date
        self.statusRaw = status.rawValue
        self.medication = medication
    }

    var status: DoseStatus {
        get { DoseStatus(rawValue: statusRaw) ?? .taken }
        set { statusRaw = newValue.rawValue }
    }
}

/// Stable identifier for one scheduled dose of one medication.
enum DoseKey {
    static func make(_ medID: UUID, _ date: Date) -> String {
        "\(medID.uuidString)|\(Int(date.timeIntervalSince1970.rounded()))"
    }

    static func parse(_ key: String) -> (medID: UUID, scheduledAt: Date)? {
        let parts = key.split(separator: "|")
        guard parts.count == 2, let id = UUID(uuidString: String(parts[0])), let secs = Double(parts[1]) else { return nil }
        return (id, Date(timeIntervalSince1970: secs))
    }
}
