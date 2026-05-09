import SwiftUI
import SwiftData
import UserNotifications

@main
struct InklingApp: App {
    let container: ModelContainer = InklingPersistence.makeContainer()

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
