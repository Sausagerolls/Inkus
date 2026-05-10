import Foundation

/// Dropbox provider — stub. The full integration needs OAuth 2.0 with PKCE,
/// the `/2/files/upload`, `/2/files/download`, `/2/files/list_folder`, and
/// `/2/files/delete_v2` endpoints, and refresh-token handling.
///
/// Surfaced as "Coming soon" in Settings → Sync until the OAuth flow ships.
struct DropboxProvider: SyncProvider {
    let kind: SyncProviderKind = .dropbox
    var isConfigured: Bool { false }

    func validateConfiguration() async throws { throw SyncProviderError.notImplemented }
    func upload(data: Data, remotePath: String) async throws { throw SyncProviderError.notImplemented }
    func download(remotePath: String) async throws -> Data? { throw SyncProviderError.notImplemented }
    func list(prefix: String) async throws -> [String] { throw SyncProviderError.notImplemented }
    func delete(remotePath: String) async throws { throw SyncProviderError.notImplemented }
}
