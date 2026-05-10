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
                .onOpenURL { url in
                    _ = OAuthURLHandler.handle(url)
                }
        }
        .modelContainer(container)
        .commands {
            // Replace the default New menu item ⌘N with one wired to NewEntryIntent.
            CommandGroup(replacing: .newItem) {
                Button("New Entry") {
                    NotificationCenter.default.post(name: .inklingNewEntryRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            // Sidebar / View menu — surfaces the things that are otherwise toolbar-only.
            CommandGroup(after: .toolbar) {
                Button("Search…") {
                    NotificationCenter.default.post(name: .inklingShowSearchRequested, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
                Button("Generate Weekly Reflection") {
                    NotificationCenter.default.post(name: .inklingShowWeeklyReflectionRequested, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            // App menu — Settings… ⌘,. `replacing:` avoids a duplicate
            // keyboard shortcut against SwiftUI's auto-generated item that
            // points at the unimplemented orderFrontPreferencesPanel: action.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .inklingShowSettingsRequested, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
