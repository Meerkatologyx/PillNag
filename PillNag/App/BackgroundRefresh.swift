import BackgroundTasks
import Foundation

/// Periodically tops up the alert horizon so nags keep coming even if the app isn't opened for days.
enum BackgroundRefresh {
    static let identifier = "com.pillnag.app.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date.now.addingTimeInterval(4 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor
    static func handle() async {
        schedule()
        await NagScheduler.shared.rescheduleAll()
    }
}
