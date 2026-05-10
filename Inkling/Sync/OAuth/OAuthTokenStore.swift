import Foundation
import Security

/// Per-provider OAuth token, persisted in the iOS Keychain. We store one
/// entry per provider keyed by `service`. Refresh-token rotation rewrites
/// the entry in place.
struct OAuthToken: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    var accountLabel: String?  // e.g. user@example.com — for the Settings UI

    var isExpired: Bool {
        guard let expiresAt else { return false }
        // Refresh 60 seconds before the wire says we should.
        return expiresAt.timeIntervalSinceNow < 60
    }
}

@MainActor
enum OAuthTokenStore {
    private static let serviceDropbox = "co.giantmushroom.inkling.oauth.dropbox"
    private static let serviceGoogle  = "co.giantmushroom.inkling.oauth.google"

    static func load(_ kind: SyncProviderKind) -> OAuthToken? {
        guard let service = service(for: kind),
              let data = readKeychain(service: service),
              let token = try? JSONDecoder().decode(OAuthToken.self, from: data) else {
            return nil
        }
        return token
    }

    @discardableResult
    static func save(_ token: OAuthToken, for kind: SyncProviderKind) -> Bool {
        guard let service = service(for: kind),
              let data = try? JSONEncoder().encode(token) else {
            return false
        }
        return writeKeychain(service: service, data: data)
    }

    @discardableResult
    static func delete(_ kind: SyncProviderKind) -> Bool {
        guard let service = service(for: kind) else { return false }
        return deleteKeychain(service: service)
    }

    // MARK: Helpers

    private static func service(for kind: SyncProviderKind) -> String? {
        switch kind {
        case .dropbox:     return serviceDropbox
        case .googleDrive: return serviceGoogle
        default:           return nil
        }
    }

    private static func writeKeychain(service: String, data: Data) -> Bool {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(baseQuery as CFDictionary)
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    private static func readKeychain(service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return data
    }

    private static func deleteKeychain(service: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}
