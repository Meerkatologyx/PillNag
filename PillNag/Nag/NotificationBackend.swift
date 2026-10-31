import Foundation
import UserNotifications

/// Local-notification fallback for when AlarmKit isn't authorized.
@MainActor
enum NotificationBackend {
    nonisolated static let category = "DOSE_NAG"
    nonisolated static let snoozeAction = "DOSE_SNOOZE"
    static let idPrefix = "nag."
    /// iOS keeps at most 64 pending local notifications per app; leave room for others.
    static let maxScheduled = 60

    private static var center: UNUserNotificationCenter { .current() }

    /// Only Snooze is offered: marking a dose taken is deliberately only possible inside the app
    /// (tapping the notification opens it).
    static func registerCategories() {
        let snooze = UNNotificationAction(identifier: snoozeAction, title: "Snooze", options: [],
                                          icon: UNNotificationActionIcon(systemImageName: "zzz"))
        let category = UNNotificationCategory(identifier: category, actions: [snooze],
                                              intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    static func isAuthorized() async -> Bool {
        let status = await authorizationStatus()
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func removeAllPendingNags() async {
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    static func replaceAll(with nags: [PlannedNag]) async {
        await removeAllPendingNags()
        let calendar = Calendar.current
        for nag in nags {
            let content = UNMutableNotificationContent()
            content.title = nag.title
            content.body = nag.body
            content.sound = nag.sound.notificationSound
            content.categoryIdentifier = category
            content.threadIdentifier = nag.doseKey
            content.interruptionLevel = .active
            content.userInfo = ["doseKey": nag.doseKey]
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: nag.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: "\(idPrefix)\(nag.doseKey)#\(nag.index)",
                                                content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    /// Clears already-delivered nags for a dose from Notification Center.
    static func removeDelivered(doseKey: String) {
        Task {
            let ids = await center.deliveredNotifications()
                .filter { ($0.request.content.userInfo["doseKey"] as? String) == doseKey }
                .map(\.request.identifier)
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    static func postLowSupply(for med: Medication) {
        let content = UNMutableNotificationContent()
        content.title = "Running low on \(med.name)"
        content.body = "Only \(med.pillsRemaining) left. Time to refill."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "supply.\(med.id.uuidString)", content: content, trigger: nil)
        center.add(request)
    }
}

/// Handles the Snooze button on notifications. Tapping the notification itself just opens the app.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard let key = response.notification.request.content.userInfo["doseKey"] as? String else { return }
        if response.actionIdentifier == NotificationBackend.snoozeAction {
            await DoseActions.handleExternal(.snoozed, doseKey: key)
        }
    }
}
