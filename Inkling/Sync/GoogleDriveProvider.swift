import Foundation

/// Google Drive provider — stub. Full integration needs Google Sign-In via
/// ASWebAuthenticationSession, the Drive v3 REST API for files.create,
/// files.get (alt=media), files.list, and files.delete, plus refresh-token
/// rotation.
///
/// Surfaced as "Coming soon" in Settings → Sync until the OAuth flow ships.
struct GoogleDriveProvider: SyncProvider {
    let kind: SyncProviderKind = .googleDrive
    var isConfigured: Bool { false }

    func validateConfiguration() async throws { throw SyncProviderError.notImplemented }
    func upload(data: Data, remotePath: String) async throws { throw SyncProviderError.notImplemented }
    func download(remotePath: String) async throws -> Data? { throw SyncProviderError.notImplemented }
    func list(prefix: String) async throws -> [String] { throw SyncProviderError.notImplemented }
    func delete(remotePath: String) async throws { throw SyncProviderError.notImplemented }
}
