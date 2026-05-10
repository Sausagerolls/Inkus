import Foundation
import UserNotifications

/// Wraps weekly-reflection local notifications. All scheduling is local;
/// no APNs / no remote push.
struct NotificationScheduler {
    static let weeklyReflectionIdentifier = "co.inkling.weeklyReflection"

    enum AuthorizationState {
        case notDetermined, denied, authorized, provisional, ephemeral

        init(_ status: UNAuthorizationStatus) {
            switch status {
            case .notDetermined: self = .notDetermined
            case .denied:        self = .denied
            case .authorized:    self = .authorized
            case .provisional:   self = .provisional
            case .ephemeral:     self = .ephemeral
            @unknown default:    self = .notDetermined
            }
        }
    }

    static func currentAuthorization() async -> AuthorizationState {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return AuthorizationState(settings.authorizationStatus)
    }

    /// Asks the user for permission. Returns true if granted (or already provisional/ephemeral).
    @discardableResult
    static func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            return false
        }
    }

    /// Schedules (or replaces) the weekly Sunday reminder at the given hour:minute (local).
    static func scheduleWeeklyReflection(hour: Int = 19, minute: Int = 0) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [weeklyReflectionIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "Your week in review is ready"
        content.body  = "Open Inkus to read this week's reflection."
        content.sound = .default

        var components = DateComponents()
        components.weekday = 1   // Sunday in Gregorian (1 = Sun)
        components.hour    = hour
        components.minute  = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: weeklyReflectionIdentifier,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    static func cancelWeeklyReflection() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [weeklyReflectionIdentifier])
    }
}
