import Foundation

/// Google Drive v3 sync. Stores files inside an "Inkling" folder created by
/// the app under the user's Drive root. Scope is `drive.file` so Inkling can
/// only see what it created — never the user's wider Drive.
actor GoogleDriveProvider: SyncProvider {
    let kind: SyncProviderKind = .googleDrive

    private let session: URLSession
    private let folderName = "Inkling"
    private var cachedFolderID: String?

    init(session: URLSession = .shared) {
        self.session = session
    }

    nonisolated var isConfigured: Bool {
        guard !OAuthConfig.GoogleDrive.clientID.isEmpty else { return false }
        return MainActor.assumeIsolated { OAuthTokenStore.load(.googleDrive) } != nil
    }

    func validateConfiguration() async throws {
        let token = try await currentAccessToken()
        // userinfo gives us the email back for the Settings UI.
        var req = URLRequest(url: URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: req)
        try expectOK(response, body: data)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let email = json["email"] as? String {
            await MainActor.run {
                if var stored = OAuthTokenStore.load(.googleDrive) {
                    stored.accountLabel = email
                    OAuthTokenStore.save(stored, for: .googleDrive)
                }
            }
        }
        _ = try await ensureRootFolder(token: token)
    }

    func upload(data: Data, remotePath: String) async throws {
        let token = try await currentAccessToken()
        let folderID = try await ensureRootFolder(token: token)
        let filename = (remotePath as NSString).lastPathComponent

        // Drive's "create" doesn't have an upsert. If a file with this name
        // exists in our folder, PATCH the media; otherwise POST a new one.
        if let existingID = try await fileID(named: filename, in: folderID, token: token) {
            try await uploadMedia(data: data, fileID: existingID, token: token)
        } else {
            try await createFile(data: data, name: filename, parentID: folderID, token: token)
        }
    }

    func download(remotePath: String) async throws -> Data? {
        let token = try await currentAccessToken()
        let folderID = try await ensureRootFolder(token: token)
        let filename = (remotePath as NSString).lastPathComponent
        guard let id = try await fileID(named: filename, in: folderID, token: token) else { return nil }
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(id)?alt=media")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: req)
        try expectOK(response, body: data)
        return data
    }

    func list(prefix: String) async throws -> [String] {
        let token = try await currentAccessToken()
        let folderID = try await ensureRootFolder(token: token)
        var results: [String] = []
        var pageToken: String?
        repeat {
            var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
            var items: [URLQueryItem] = [
                .init(name: "q", value: "'\(folderID)' in parents and trashed = false"),
                .init(name: "spaces", value: "drive"),
                .init(name: "fields", value: "nextPageToken, files(id, name)"),
                .init(name: "pageSize", value: "1000"),
            ]
            if let pageToken { items.append(.init(name: "pageToken", value: pageToken)) }
            components.queryItems = items
            var req = URLRequest(url: components.url!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: req)
            try expectOK(response, body: data)
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let files = (json["files"] as? [[String: Any]]) ?? []
            for f in files {
                if let name = f["name"] as? String { results.append(name) }
            }
            pageToken = json["nextPageToken"] as? String
        } while pageToken != nil
        return results
    }

    func delete(remotePath: String) async throws {
        let token = try await currentAccessToken()
        let folderID = try await ensureRootFolder(token: token)
        let filename = (remotePath as NSString).lastPathComponent
        guard let id = try await fileID(named: filename, in: folderID, token: token) else { return }
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(id)")!)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 { return }
        try expectOK(response, body: data)
    }

    // MARK: Internals

    private func ensureRootFolder(token: String) async throws -> String {
        if let cachedFolderID { return cachedFolderID }
        // Look for an existing folder first.
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            .init(name: "q", value: "name = '\(folderName)' and mimeType = 'application/vnd.google-apps.folder' and trashed = false"),
            .init(name: "spaces", value: "drive"),
            .init(name: "fields", value: "files(id)"),
            .init(name: "pageSize", value: "1"),
        ]
        var req = URLRequest(url: components.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: req)
        try expectOK(response, body: data)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if let files = json["files"] as? [[String: Any]],
           let first = files.first,
           let id = first["id"] as? String {
            cachedFolderID = id
            return id
        }
        // Otherwise create it.
        var createReq = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files")!)
        createReq.httpMethod = "POST"
        createReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        createReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "name": folderName,
            "mimeType": "application/vnd.google-apps.folder",
        ]
        createReq.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (createData, createResponse) = try await session.data(for: createReq)
        try expectOK(createResponse, body: createData)
        let createJSON = (try? JSONSerialization.jsonObject(with: createData) as? [String: Any]) ?? [:]
        guard let id = createJSON["id"] as? String else {
            throw SyncProviderError.decoding(message: "missing folder id")
        }
        cachedFolderID = id
        return id
    }

    private func fileID(named name: String, in folderID: String, token: String) async throws -> String? {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        let escapedName = name.replacingOccurrences(of: "'", with: "\\'")
        components.queryItems = [
            .init(name: "q", value: "name = '\(escapedName)' and '\(folderID)' in parents and trashed = false"),
            .init(name: "spaces", value: "drive"),
            .init(name: "fields", value: "files(id)"),
            .init(name: "pageSize", value: "1"),
        ]
        var req = URLRequest(url: components.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: req)
        try expectOK(response, body: data)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let files = (json["files"] as? [[String: Any]]) ?? []
        return files.first?["id"] as? String
    }

    private func createFile(data: Data, name: String, parentID: String, token: String) async throws {
        // Multipart upload: metadata JSON part + media part.
        let boundary = "inkling-\(UUID().uuidString)"
        let metadata: [String: Any] = ["name": name, "parents": [parentID]]
        let metadataJSON = try JSONSerialization.data(withJSONObject: metadata)
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metadataJSON)
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--".data(using: .utf8)!)

        var req = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (resp, response) = try await session.upload(for: req, from: body)
        try expectOK(response, body: resp)
    }

    private func uploadMedia(data: Data, fileID: String, token: String) async throws {
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files/\(fileID)?uploadType=media")!)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (resp, response) = try await session.upload(for: req, from: data)
        try expectOK(response, body: resp)
    }

    // MARK: Token management

    private func currentAccessToken() async throws -> String {
        let stored = await MainActor.run { OAuthTokenStore.load(.googleDrive) }
        guard let stored else { throw SyncProviderError.notConfigured }
        if !stored.isExpired { return stored.accessToken }
        let refreshed = try await OAuthHelper.shared.refresh(
            kind: .googleDrive,
            clientID: OAuthConfig.GoogleDrive.clientID,
            tokenURL: OAuthConfig.GoogleDrive.tokenURL
        )
        return refreshed.accessToken
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
