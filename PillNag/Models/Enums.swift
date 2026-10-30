import SwiftUI

enum PillShape: String, CaseIterable, Identifiable, Codable {
    case round, capsule, oval, oblong, diamond, triangle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .round: "Round"
        case .capsule: "Capsule"
        case .oval: "Oval"
        case .oblong: "Oblong"
        case .diamond: "Diamond"
        case .triangle: "Triangle"
        }
    }
}

enum ScheduleKind: String, CaseIterable, Identifiable, Codable {
    case daily, weekdays, interval, asNeeded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: "Daily"
        case .weekdays: "Weekdays"
        case .interval: "Every X hrs"
        case .asNeeded: "As needed"
        }
    }

    var symbol: String {
        switch self {
        case .daily: "sun.max"
        case .weekdays: "calendar"
        case .interval: "clock.arrow.circlepath"
        case .asNeeded: "hand.raised"
        }
    }
}

enum DoseStatus: String, Codable {
    case taken, skipped, snoozed
}

/// Curated SF Symbols offered in the icon picker.
enum MedSymbols {
    static let all: [String] = [
        "pills.fill", "pill.fill", "capsule.fill", "cross.case.fill", "cross.vial.fill",
        "drop.fill", "syringe.fill", "bandage.fill", "heart.fill", "bolt.heart.fill",
        "lungs.fill", "brain.head.profile", "eye.fill", "leaf.fill", "sun.max.fill",
        "moon.fill", "allergens", "staroflife.fill", "testtube.2", "waveform.path.ecg",
    ]
}

/// Preset pill colors (hex).
enum PillPalette {
    static let colors: [String] = [
        "#FF5E78", "#FF9F43", "#FECA57", "#2ED573", "#1DD1A1", "#48DBFB",
        "#54A0FF", "#5E6BE6", "#A55EEA", "#F368E0", "#FAFAFF", "#8395A7",
    ]
}
