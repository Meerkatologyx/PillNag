import SwiftUI
import SwiftData
import UserNotifications

@main
struct PillNagApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        NotificationBackend.registerCategories()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(Persistence.container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                NagScheduler.shared.requestReschedule()
            } else if phase == .background {
                BackgroundRefresh.schedule()
            }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await BackgroundRefresh.handle()
        }
    }
}
