import Foundation
import SwiftData

enum InklingPersistence {
    /// Schema for Inkling. Order matters for migrations down the line.
    static let schema = Schema([
        Journal.self,
        Entry.self,
        WeeklyReflection.self,
        DailyPrompt.self,
    ])

    /// Production container. CloudKit deferred to Phase 5.
    @MainActor
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        do {
            let container = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
            seedIfNeeded(container: container)
            return container
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    /// Inserts a default "Personal" journal the first time the store is created.
    @MainActor
    private static func seedIfNeeded(container: ModelContainer) {
        let context = container.mainContext
        let descriptor = FetchDescriptor<Journal>()
        let existing = (try? context.fetchCount(descriptor)) ?? 0
        guard existing == 0 else { return }

        let personal = Journal(
            name: "Personal",
            iconName: "book.closed",
            accentColorHex: "#4F46E5",
            sortOrder: 0
        )
        context.insert(personal)
        try? context.save()
    }
}
