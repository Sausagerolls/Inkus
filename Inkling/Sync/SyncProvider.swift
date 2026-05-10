import Foundation

/// Abstracts where Inkling's text + attachments sync. The CloudKit path is
/// handled by SwiftData itself when `cloudKitDatabase: .private(...)` is set
/// on the model container — the `ICloudProvider` here is a status-only stub.
///
/// Adding a new provider means implementing this protocol, persisting the
/// account credentials (in the system Keychain), and writing serialised
/// snapshots of the SwiftData store on a schedule. The real sync engine
/// lives in `SyncCoordinator` (Phase 7+ work).
enum SyncProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case iCloud
    case nextcloud
    case dropbox
    case googleDrive

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:        return "No sync (local only)"
        case .iCloud:      return "iCloud (Apple)"
        case .nextcloud:   return "Nextcloud"
        case .dropbox:     return "Dropbox"
        case .googleDrive: return "Google Drive"
        }
    }

    var shortName: String {
        switch self {
        case .none:        return "Local"
        case .iCloud:      return "iCloud"
        case .nextcloud:   return "Nextcloud"
        case .dropbox:     return "Dropbox"
        case .googleDrive: return "Drive"
        }
    }

    /// SF Symbol used as a fallback when there's no brand asset.
    var symbol: String {
        switch self {
        case .none:        return "iphone"
        case .iCloud:      return "icloud"
        case .nextcloud:   return "server.rack"
        case .dropbox:     return "shippingbox"
        case .googleDrive: return "g.circle"
        }
    }

    /// Asset catalog name when we ship a real brand logo for this provider.
    /// Returns nil when we should use the SF Symbol fallback.
    var assetName: String? {
        switch self {
        case .dropbox:     return "logo-dropbox"
        case .googleDrive: return "logo-googledrive"
        default:           return nil
        }
    }
}

/// A single sync attempt's result, surfaced in Settings.
enum SyncStatus: Equatable, Sendable {
    case idle
    case syncing
    case ok(at: Date)
    case error(message: String)
}

/// Protocol every provider conforms to. Methods are async and throw on failure.
protocol SyncProvider: Sendable {
    var kind: SyncProviderKind { get }
    var isConfigured: Bool { get }

    /// Quick reachability ping. Throws on failure.
    func validateConfiguration() async throws

    /// Push the given file payload up. The remote path is relative to the
    /// app's sync root.
    func upload(data: Data, remotePath: String) async throws

    /// Fetch a remote file. Returns nil if the file does not exist.
    func download(remotePath: String) async throws -> Data?

    /// List remote files. Each entry is a relative path.
    func list(prefix: String) async throws -> [String]

    /// Delete a remote file. No-op if the file is already missing.
    func delete(remotePath: String) async throws
}

enum SyncProviderError: Error {
    case notImplemented
    case notConfigured
    case http(status: Int, body: String?)
    case decoding(message: String)
    case underlying(any Error)
}
