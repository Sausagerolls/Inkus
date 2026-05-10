import Foundation
import Observation
import Security

/// Persists the user's chosen sync provider + Nextcloud credentials in the
/// Keychain. Selection is stored in UserDefaults; the password lives in the
/// Keychain so it never lands in a backup or a SwiftData store dump.
@MainActor
@Observable
final class SyncSettingsStore {
    static let shared = SyncSettingsStore()

    private let kindKey = "co.giantmushroom.inkling.syncProvider"
    private let nextcloudURLKey = "co.giantmushroom.inkling.nextcloud.url"
    private let nextcloudUserKey = "co.giantmushroom.inkling.nextcloud.user"
    private let nextcloudPasswordService = "co.giantmushroom.inkling.nextcloud.appPassword"

    var selectedKind: SyncProviderKind {
        didSet { UserDefaults.standard.set(selectedKind.rawValue, forKey: kindKey) }
    }
    var nextcloudURL: String {
        didSet { UserDefaults.standard.set(nextcloudURL, forKey: nextcloudURLKey) }
    }
    var nextcloudUser: String {
        didSet { UserDefaults.standard.set(nextcloudUser, forKey: nextcloudUserKey) }
    }
    var nextcloudPassword: String {
        didSet { writePassword(nextcloudPassword) }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: kindKey) ?? SyncProviderKind.iCloud.rawValue
        self.selectedKind = SyncProviderKind(rawValue: raw) ?? .iCloud
        self.nextcloudURL = UserDefaults.standard.string(forKey: nextcloudURLKey) ?? ""
        self.nextcloudUser = UserDefaults.standard.string(forKey: nextcloudUserKey) ?? ""
        self.nextcloudPassword = Self.readPassword(service: nextcloudPasswordService) ?? ""
    }

    var nextcloudCredentials: NextcloudCredentials {
        NextcloudCredentials(
            serverURL: nextcloudURL,
            username: nextcloudUser,
            appPassword: nextcloudPassword
        )
    }

    /// Returns a fresh provider instance for the currently selected kind.
    func currentProvider() -> any SyncProvider {
        switch selectedKind {
        case .none:        return LocalOnlyProvider()
        case .iCloud:      return ICloudProvider()
        case .nextcloud:   return NextcloudProvider(credentials: nextcloudCredentials)
        case .dropbox:     return DropboxProvider()
        case .googleDrive: return GoogleDriveProvider()
        }
    }

    // MARK: Keychain helpers

    private func writePassword(_ value: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: nextcloudPasswordService,
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func readPassword(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }
}
