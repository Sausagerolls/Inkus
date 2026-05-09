import AppIntents

/// Mirror of the same intent in the main app. Declaring it in the widget target
/// lets the medium widget's "Start writing" button reference it directly.
/// iOS routes the run to the main app (openAppWhenRun = true) where the
/// app-target copy of this intent posts the notification that opens the editor.
struct NewEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "New entry"
    static let description: IntentDescription = IntentDescription(
        "Open Inkling and start a new journal entry."
    )
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // No-op in the widget process; the app-side perform() runs on launch.
        return .result()
    }
}
