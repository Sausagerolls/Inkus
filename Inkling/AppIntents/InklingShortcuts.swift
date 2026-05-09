import AppIntents

/// Surfaces NewEntryIntent in the Shortcuts app and Spotlight without the user
/// having to build it manually.
struct InklingShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewEntryIntent(),
            phrases: [
                "New entry in \(.applicationName)",
                "Write in \(.applicationName)",
                "Start a journal entry in \(.applicationName)",
            ],
            shortTitle: "New Entry",
            systemImageName: "square.and.pencil"
        )
    }
}
