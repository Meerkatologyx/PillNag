import AppIntents
import Foundation

/// Runs when the alarm's "Stop" button is pressed. It never marks the dose taken; it only tops up
/// the booked alarms so long and endless nag chains keep going.
struct RefreshNagsIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Keep Nagging"
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await NagScheduler.shared.rescheduleAll()
        return .result()
    }
}

/// Runs when the alarm's "Snooze" button is pressed.
struct SnoozeDoseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Snooze Dose"
    static let isDiscoverable = false

    @Parameter(title: "Dose")
    var doseKey: String

    init() {}

    init(doseKey: String) {
        self.doseKey = doseKey
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await DoseActions.handleExternal(.snoozed, doseKey: doseKey)
        return .result()
    }
}
