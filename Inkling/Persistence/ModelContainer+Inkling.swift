import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "com.giantmushroom.Inkling", category: "Persistence")

enum InklingPersistence {
    /// Schema for Inkling. Order matters for migrations down the line.
    static let schema = Schema([
        Journal.self,
        Entry.self,
        WeeklyReflection.self,
        DailyPrompt.self,
    ])

    /// CloudKit container identifier — must match the iCloud capability set in Xcode.
    static let cloudKitContainerID = "iCloud.com.giantmushroom.Inkling"

    /// Shared App Group identifier — must match the App Group capability and be set
    /// on both the app and the widget extension target.
    static let appGroupID = "group.com.giantmushroom.Inkling"

    /// Production container. Tries CloudKit + App Group first; falls back to a
    /// local-only store if entitlements aren't in place yet (so the app still
    /// runs during incremental Xcode setup).
    @MainActor
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        if inMemory {
            return makeInMemory()
        }

        if let cloud = try? makeCloudKit() {
            seedIfNeeded(container: cloud)
            return cloud
        }

        logger.warning("CloudKit container init failed — falling back to local store. Check iCloud + App Group capabilities in Xcode.")
        let local = makeLocal()
        seedIfNeeded(container: local)
        return local
    }

    // MARK: Variants

    @MainActor
    private static func makeInMemory() -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        seedIfNeeded(container: container)
        return container
    }

    @MainActor
    private static func makeCloudKit() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .identifier(appGroupID),
            cloudKitDatabase: .private(cloudKitContainerID)
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @MainActor
    private static func makeLocal() -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create local ModelContainer: \(error)")
        }
    }

    // MARK: Seed

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
            ("Personal", "book.closed", "#4F46E5", 0),
            ("Work",     "briefcase",   "#C05621", 1),
            ("Travel",   "suitcase",    "#2F855A", 2),
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
