import Foundation

/// Explicit "no sync" provider. Selecting this means Inkus reads and writes
/// only from the on-device SwiftData store. CloudKit container is still
/// configured at the SwiftData level (so opting back in to iCloud later is
/// frictionless), but no third-party network calls are made for sync.
struct LocalOnlyProvider: SyncProvider {
    let kind: SyncProviderKind = .none
    var isConfigured: Bool { true }

    func validateConfiguration() async throws {}
    func upload(data: Data, remotePath: String) async throws {}
    func download(remotePath: String) async throws -> Data? { nil }
    func list(prefix: String) async throws -> [String] { [] }
    func delete(remotePath: String) async throws {}
}
