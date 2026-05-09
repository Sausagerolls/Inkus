import AppIntents
import SwiftUI

/// "New entry in Inkling" — exposed to Shortcuts, Spotlight, and the medium widget's
/// Start writing button. Opens the app and signals the main UI to present a fresh draft.
struct NewEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "New entry"
    static let description: IntentDescription = IntentDescription(
        "Open Inkling and start a new journal entry."
    )
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // RootView listens for this notification and presents the editor.
        NotificationCenter.default.post(name: .inklingNewEntryRequested, object: nil)
        return .result()
    }
}

extension Notification.Name {
    static let inklingNewEntryRequested = Notification.Name("co.giantmushroom.inkling.newEntryRequested")
}
