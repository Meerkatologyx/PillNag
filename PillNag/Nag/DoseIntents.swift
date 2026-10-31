import AppIntents
import Foundation

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
