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

    /// Inserts default journals the first time the store is created.
    /// Idempotent — checks existing names so re-runs after upgrades won't duplicate.
    @MainActor
    private static func seedIfNeeded(container: ModelContainer) {
        let context = container.mainContext
        let existingNames: Set<String> = {
            let descriptor = FetchDescriptor<Journal>()
            let journals = (try? context.fetch(descriptor)) ?? []
            return Set(journals.map(\.name))
        }()

        let defaults: [(name: String, icon: String, hex: String, order: Int)] = [
            ("Personal", "book.closed", "#4F46E5", 0),  // indigo
            ("Work",     "briefcase",   "#C05621", 1),  // terracotta
            ("Travel",   "suitcase",    "#2F855A", 2),  // forest
        ]

        var inserted = false
        for spec in defaults where !existingNames.contains(spec.name) {
            context.insert(Journal(
                name: spec.name,
                iconName: spec.icon,
                accentColorHex: spec.hex,
                sortOrder: spec.order
            ))
            inserted = true
        }
        if inserted { try? context.save() }
    }
}
