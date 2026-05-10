import Foundation

/// Nextcloud sync over WebDAV. Stores everything under
/// `<server>/remote.php/dav/files/<username>/Inkling/` using HTTP Basic auth
/// with an app password (Settings → Security → "Generate app password" in
/// Nextcloud).
///
/// We avoid pulling in a third-party WebDAV SDK; the protocol surface we need
/// is small enough (PUT, GET, PROPFIND, MKCOL, DELETE) to hand-roll on
/// URLSession. Keeps the dependency footprint at zero.
struct NextcloudCredentials: Codable, Equatable, Sendable {
    var serverURL: String   // e.g. "https://cloud.example.com"
    var username: String
    var appPassword: String // Nextcloud app password, NOT the account password

    /// The base directory we sync to/from. Always under the user's home.
    var rootFolder: String { "Inkling" }
}

actor NextcloudProvider: SyncProvider {
    let kind: SyncProviderKind = .nextcloud
    private let credentials: NextcloudCredentials
    private let session: URLSession

    var isConfigured: Bool {
        !credentials.serverURL.isEmpty &&
        !credentials.username.isEmpty &&
        !credentials.appPassword.isEmpty
    }

    init(credentials: NextcloudCredentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    func validateConfiguration() async throws {
        guard isConfigured else { throw SyncProviderError.notConfigured }
        // Try a PROPFIND on the user's home — the cheapest "is auth working?"
        // request that Nextcloud exposes.
        var req = try makeRequest(method: "PROPFIND", path: "")
        req.setValue("0", forHTTPHeaderField: "Depth")
        let (_, response) = try await session.data(for: req)
        try expectOK(response)
    }

    func upload(data: Data, remotePath: String) async throws {
        try await ensureRootExists()
        var req = try makeRequest(method: "PUT", path: remotePath)
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.upload(for: req, from: data)
        try expectOK(response)
    }

    func download(remotePath: String) async throws -> Data? {
        let req = try makeRequest(method: "GET", path: remotePath)
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            return nil
        }
        try expectOK(response)
        return data
    }

    func list(prefix: String) async throws -> [String] {
        var req = try makeRequest(method: "PROPFIND", path: prefix)
        req.setValue("1", forHTTPHeaderField: "Depth")
        req.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        req.httpBody = """
        <?xml version="1.0"?>
        <d:propfind xmlns:d="DAV:"><d:prop><d:displayname/></d:prop></d:propfind>
        """.data(using: .utf8)
        let (data, response) = try await session.data(for: req)
        try expectOK(response)
        guard let xml = String(data: data, encoding: .utf8) else {
            throw SyncProviderError.decoding(message: "non-utf8 propfind body")
        }
        // Cheap regex parse — Nextcloud always emits <d:href>...</d:href>.
        let hrefs = xml
            .components(separatedBy: "<d:href>")
            .dropFirst()
            .compactMap { $0.components(separatedBy: "</d:href>").first }
        let basePath = "/remote.php/dav/files/\(credentials.username)/\(credentials.rootFolder)/"
        return hrefs
            .compactMap { $0.removingPercentEncoding }
            .compactMap { href -> String? in
                guard let range = href.range(of: basePath) else { return nil }
                let suffix = href[range.upperBound...]
                return suffix.isEmpty ? nil : String(suffix)
            }
    }

    func delete(remotePath: String) async throws {
        let req = try makeRequest(method: "DELETE", path: remotePath)
        let (_, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            return
        }
        try expectOK(response)
    }

    // MARK: Helpers

    private func makeRequest(method: String, path: String) throws -> URLRequest {
        let trimmedServer = credentials.serverURL.trimmingCharacters(in: .init(charactersIn: "/"))
        let pathComponent = path.isEmpty
            ? credentials.rootFolder
            : "\(credentials.rootFolder)/\(path)"
        let urlString = "\(trimmedServer)/remote.php/dav/files/\(credentials.username)/\(pathComponent)"
        guard let url = URL(string: urlString) else {
            throw SyncProviderError.decoding(message: "bad URL: \(urlString)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        let basic = "\(credentials.username):\(credentials.appPassword)"
            .data(using: .utf8)!
            .base64EncodedString()
        req.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        req.setValue("Inkling/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        return req
    }

    private func ensureRootExists() async throws {
        var req = try makeRequest(method: "MKCOL", path: "")
        let (_, response) = try await session.data(for: req)
        // 201 Created on first time, 405 Method Not Allowed when it already
        // exists. Either is fine. Anything else surfaces as an error.
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 201 || http.statusCode == 405 { return }
            throw SyncProviderError.http(status: http.statusCode, body: nil)
        }
    }

    private func expectOK(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw SyncProviderError.decoding(message: "non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SyncProviderError.http(status: http.statusCode, body: nil)
        }
    }
}
