import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "com.giantmushroom.Inkling", category: "Persistence")

enum InkusPersistence {
    /// Schema for Inkling. Order matters for migrations down the line.
    static let schema = Schema([
        Journal.self,
        Entry.self,
        WeeklyReflection.self,
        DailyPrompt.self,
        Attachment.self,
    ])

    /// CloudKit container identifier — must match the iCloud capability set in Xcode.
    static let cloudKitContainerID = "iCloud.com.giantmushroom.Inkling"

    /// Shared App Group identifier — must match the App Group capability and be set
    /// on both the app and the widget extension target.
    static let appGroupID = "group.com.giantmushroom.Inkling"

    /// Diagnostic — set during makeContainer() so the Settings UI can display
    /// whether the active store is CloudKit-backed or fell back to local-only.
    enum BackingStore: Equatable {
        case cloudKit
        case local
        case localFallback(reason: String)
        case inMemory
    }
    @MainActor static private(set) var activeBackingStore: BackingStore = .local

    /// Production container. Tries CloudKit + App Group first; falls back to a
    /// local-only store if entitlements aren't in place yet (so the app still
    /// runs during incremental Xcode setup).
    @MainActor
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        if inMemory {
            activeBackingStore = .inMemory
            return makeInMemory()
        }

        do {
            let cloud = try makeCloudKit()
            seedIfNeeded(container: cloud)
            AttachmentStore.migrateLegacyFilesIfNeeded(in: cloud.mainContext)
            activeBackingStore = .cloudKit
            logger.info("ModelContainer: CloudKit private DB active (\(cloudKitContainerID))")
            return cloud
        } catch {
            let reason = (error as NSError).localizedDescription
            logger.warning("CloudKit container init failed (\(reason)) — falling back to local store. Check iCloud + App Group capabilities in Xcode.")
            let local = makeLocal()
            seedIfNeeded(container: local)
            AttachmentStore.migrateLegacyFilesIfNeeded(in: local.mainContext)
            activeBackingStore = .localFallback(reason: reason)
            return local
        }
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

    /// Key in NSUbiquitousKeyValueStore — set the first time defaults are
    /// seeded for this Apple ID. iCloud key-value sync mirrors it across the
    /// user's devices so a second device skips the local seed even if its
    /// CloudKit store hasn't replicated the existing journals yet. Bumping
    /// the suffix invalidates the flag and re-seeds on every device.
    private static let seededFlagKey = "co.giantmushroom.inkling.hasSeededDefaultsV1"

    /// Inserts default journals the first time the store is created on this
    /// Apple ID. Uses NSUbiquitousKeyValueStore as the cross-device "I've
    /// already seeded" flag so we don't end up with two Personal/Work/Travel
    /// triples after a second device launches before CloudKit has a chance
    /// to deliver the originals.
    @MainActor
    private static func seedIfNeeded(container: ModelContainer) {
        let context = container.mainContext

        // Always run the merge pass first — even if the seed is skipped,
        // existing duplicates from earlier versions need to be reconciled.
        dedupeJournalsByName(in: context)

        let cloudKVS = NSUbiquitousKeyValueStore.default
        cloudKVS.synchronize()
        if cloudKVS.bool(forKey: seededFlagKey) {
            return  // Some device on this Apple ID already seeded.
        }

        // Fall back to local UserDefaults too — if iCloud KVS is unreachable
        // (no iCloud account, network down) we don't want to seed every launch.
        let localDefaults = UserDefaults.standard
        if localDefaults.bool(forKey: seededFlagKey) {
            return
        }

        // Belt + braces: also skip if any journals already exist locally.
        // Catches the case where the user installed a pre-KVS build and is
        // upgrading. Their journals are already there; don't add a second set.
        let existingCount = (try? context.fetchCount(FetchDescriptor<Journal>())) ?? 0
        guard existingCount == 0 else {
            cloudKVS.set(true, forKey: seededFlagKey)
            cloudKVS.synchronize()
            localDefaults.set(true, forKey: seededFlagKey)
            return
        }

        let defaults: [(name: String, icon: String, hex: String, order: Int)] = [
            ("Personal", "book.closed", "#4F46E5", 0),
            ("Work",     "briefcase",   "#C05621", 1),
            ("Travel",   "suitcase",    "#2F855A", 2),
        ]
        for spec in defaults {
            context.insert(Journal(
                name: spec.name,
                iconName: spec.icon,
                accentColorHex: spec.hex,
                sortOrder: spec.order
            ))
        }
        try? context.save()

        cloudKVS.set(true, forKey: seededFlagKey)
        cloudKVS.synchronize()
        localDefaults.set(true, forKey: seededFlagKey)
    }

    /// Cleans up the existing-installs case where two devices each ran the
    /// initial seed before CloudKit synced. Groups journals by exact name.
    /// For each group with >1 row, picks the oldest (`createdAt` then
    /// lowest `id` for ties) as canonical, reassigns its entries +
    /// reflections, and deletes the duplicates. Idempotent.
    @MainActor
    static func dedupeJournalsByName(in context: ModelContext) {
        guard let allJournals = try? context.fetch(FetchDescriptor<Journal>()),
              !allJournals.isEmpty else { return }
        let grouped = Dictionary(grouping: allJournals, by: \.name)
        var didChange = false
        for (_, group) in grouped where group.count > 1 {
            let sorted = group.sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            let canonical = sorted[0]
            for dup in sorted.dropFirst() {
                for entry in dup.entries ?? [] {
                    entry.journal = canonical
                }
                for reflection in dup.reflections ?? [] {
                    reflection.journal = canonical
                }
                context.delete(dup)
                didChange = true
            }
        }
        if didChange { try? context.save() }
    }
}
