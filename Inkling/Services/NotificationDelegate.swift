import Foundation
import UserNotifications

/// Handles taps on Inkling-scheduled local notifications. Posts an in-process
/// notification so EntryListView can react (e.g. open the weekly reflection).
@MainActor
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    /// Show foreground notifications as banners + sound.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .badge]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let id = response.notification.request.identifier
        if id == NotificationScheduler.weeklyReflectionIdentifier {
            await MainActor.run {
                NotificationCenter.default.post(name: .inklingShowWeeklyReflectionRequested, object: nil)
            }
        }
    }
}

extension Notification.Name {
    static let inklingShowWeeklyReflectionRequested = Notification.Name("co.giantmushroom.inkling.showWeeklyReflectionRequested")
    /// Posted by the macOS menu bar (Edit → Find / ⌘F).
    static let inklingShowSearchRequested = Notification.Name("co.giantmushroom.inkling.showSearchRequested")
    /// Posted by the macOS menu bar (Inkling → Settings… / ⌘,).
    static let inklingShowSettingsRequested = Notification.Name("co.giantmushroom.inkling.showSettingsRequested")
}
