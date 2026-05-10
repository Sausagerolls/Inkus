import Foundation

/// Dropbox v2 sync. Files live under `/Inkus` in the user's Dropbox.
/// Auth is PKCE OAuth via OAuthHelper. Tokens persist in the iOS Keychain.
actor DropboxProvider: SyncProvider {
    let kind: SyncProviderKind = .dropbox

    private let session: URLSession
    private let rootFolder = "/Inkus"

    init(session: URLSession = .shared) {
        self.session = session
    }

    nonisolated var isConfigured: Bool {
        // Configured if there's a token on disk and an app key in Info.plist.
        guard !OAuthConfig.Dropbox.appKey.isEmpty else { return false }
        return MainActor.assumeIsolated { OAuthTokenStore.load(.dropbox) } != nil
    }

    func validateConfiguration() async throws {
        let token = try await currentAccessToken()
        // /2/users/get_current_account is the cheapest signed-in ping.
        var req = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/users/get_current_account")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = "null".data(using: .utf8) // Dropbox quirk: GET-style endpoints want literal null
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: req)
        try expectOK(response, body: data)
        // Stash the email back on the token so Settings can show it.
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let email = json["email"] as? String {
            await MainActor.run {
                if var stored = OAuthTokenStore.load(.dropbox) {
                    stored.accountLabel = email
                    OAuthTokenStore.save(stored, for: .dropbox)
                }
            }
        }
    }

    func upload(data: Data, remotePath: String) async throws {
        let token = try await currentAccessToken()
        let path = absolutePath(remotePath)
        let arg: [String: Any] = [
            "path": path,
            "mode": "overwrite",
            "autorename": false,
            "mute": true,
        ]
        let argJSON = try JSONSerialization.data(withJSONObject: arg)
        var req = URLRequest(url: URL(string: "https://content.dropboxapi.com/2/files/upload")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.setValue(String(data: argJSON, encoding: .utf8), forHTTPHeaderField: "Dropbox-API-Arg")
        let (resp, response) = try await session.upload(for: req, from: data)
        try expectOK(response, body: resp)
    }

    func download(remotePath: String) async throws -> Data? {
        let token = try await currentAccessToken()
        let path = absolutePath(remotePath)
        let arg = ["path": path]
        let argJSON = try JSONSerialization.data(withJSONObject: arg)
        var req = URLRequest(url: URL(string: "https://content.dropboxapi.com/2/files/download")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(String(data: argJSON, encoding: .utf8), forHTTPHeaderField: "Dropbox-API-Arg")
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode == 409 {
            // 409 + path/not_found is Dropbox's "file missing".
            return nil
        }
        try expectOK(response, body: data)
        return data
    }

    func list(prefix: String) async throws -> [String] {
        let token = try await currentAccessToken()
        let path = absolutePath(prefix)
        let arg: [String: Any] = [
            "path": path.isEmpty ? rootFolder : path,
            "recursive": true,
            "include_deleted": false,
            "include_media_info": false,
        ]
        let argJSON = try JSONSerialization.data(withJSONObject: arg)
        var results: [String] = []
        var req = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/files/list_folder")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = argJSON
        var (data, response) = try await session.data(for: req)
        try expectOK(response, body: data)

        var hasMore = true
        var cursor: String?
        while hasMore {
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let entries = (json["entries"] as? [[String: Any]]) ?? []
            for entry in entries where (entry[".tag"] as? String) == "file" {
                if let p = entry["path_lower"] as? String {
                    let stripped = p.hasPrefix(rootFolder.lowercased() + "/")
                        ? String(p.dropFirst(rootFolder.count + 1))
                        : p
                    results.append(stripped)
                }
            }
            cursor = json["cursor"] as? String
            hasMore = (json["has_more"] as? Bool) == true
            if hasMore, let cursor {
                var continueReq = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/files/list_folder/continue")!)
                continueReq.httpMethod = "POST"
                continueReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                continueReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                continueReq.httpBody = try JSONSerialization.data(withJSONObject: ["cursor": cursor])
                (data, response) = try await session.data(for: continueReq)
                try expectOK(response, body: data)
            }
        }
        return results
    }

    func delete(remotePath: String) async throws {
        let token = try await currentAccessToken()
        let arg = ["path": absolutePath(remotePath)]
        var req = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/files/delete_v2")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: arg)
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode == 409 { return }
        try expectOK(response, body: data)
    }

    // MARK: Token management

    /// Returns a non-expired access token, refreshing if necessary. Throws if
    /// the user hasn't signed in yet.
    private func currentAccessToken() async throws -> String {
        let stored = await MainActor.run { OAuthTokenStore.load(.dropbox) }
        guard let stored else {
            throw SyncProviderError.notConfigured
        }
        if !stored.isExpired { return stored.accessToken }
        // Refresh.
        let refreshed = try await OAuthHelper.shared.refresh(
            kind: .dropbox,
            clientID: OAuthConfig.Dropbox.appKey,
            tokenURL: OAuthConfig.Dropbox.tokenURL
        )
        return refreshed.accessToken
    }

    private nonisolated func absolutePath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmed.isEmpty { return rootFolder }
        return "\(rootFolder)/\(trimmed)"
    }

    private nonisolated func expectOK(_ response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw SyncProviderError.decoding(message: "non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: body, encoding: .utf8) ?? ""
            throw SyncProviderError.http(status: http.statusCode, body: message)
        }
    }
}
