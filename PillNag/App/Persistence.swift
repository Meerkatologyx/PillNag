import Foundation
import SwiftData

@MainActor
enum Persistence {
    static let container: ModelContainer = {
        let schema = Schema([Medication.self, DoseEvent.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false,
                                        groupContainer: .none, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not open the PillNag database: \(error)")
        }
    }()

    static var context: ModelContext { container.mainContext }

    static func medication(id: UUID) -> Medication? {
        let descriptor = FetchDescriptor<Medication>(predicate: #Predicate<Medication> { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    static func event(doseKey: String) -> DoseEvent? {
        let descriptor = FetchDescriptor<DoseEvent>(predicate: #Predicate<DoseEvent> { $0.doseKey == doseKey })
        return try? context.fetch(descriptor).first
    }
}
