import Foundation

/// CloudKit handles real syncing transparently via SwiftData. This provider
/// exists so the picker has a uniform `SyncProvider` for every backend.
struct ICloudProvider: SyncProvider {
    let kind: SyncProviderKind = .iCloud
    var isConfigured: Bool { true }

    func validateConfiguration() async throws {
        // The model container's CloudKit reachability is surfaced via
        // InkusPersistence.activeBackingStore — Settings reads that
        // directly. Nothing to ping here.
    }

    func upload(data: Data, remotePath: String) async throws {}
    func download(remotePath: String) async throws -> Data? { nil }
    func list(prefix: String) async throws -> [String] { [] }
    func delete(remotePath: String) async throws {}
}
