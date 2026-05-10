import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

/// Handles the PKCE OAuth 2.0 dance via ASWebAuthenticationSession. Same code
/// path for Dropbox and Drive — only the URLs and scopes differ.
@MainActor
final class OAuthHelper: NSObject, ASWebAuthenticationPresentationContextProviding {

    enum OAuthError: Error, LocalizedError {
        case missingClientID
        case userCancelled
        case noAuthCode
        case tokenExchangeFailed(message: String)
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .missingClientID:           return "Missing Dropbox or Google client identifier."
            case .userCancelled:             return "Sign-in was cancelled."
            case .noAuthCode:                return "The provider didn't return an authorisation code."
            case .tokenExchangeFailed(let m):return "Token exchange failed: \(m)"
            case .decodingFailed:            return "Couldn't decode the token response."
            }
        }
    }

    static let shared = OAuthHelper()
    private override init() { super.init() }

    // MARK: Public

    /// Run the full PKCE flow. Returns a stored OAuthToken on success.
    @discardableResult
    func signIn(
        kind: SyncProviderKind,
        clientID: String,
        authorizationURL: URL,
        tokenURL: URL,
        redirectURI: String,
        scopes: [String],
        extraAuthParams: [String: String] = [:]
    ) async throws -> OAuthToken {
        guard !clientID.isEmpty else { throw OAuthError.missingClientID }

        let codeVerifier = Self.makeCodeVerifier()
        let codeChallenge = Self.codeChallenge(for: codeVerifier)

        var components = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "code_challenge", value: codeChallenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]
        if !scopes.isEmpty {
            items.append(.init(name: "scope", value: scopes.joined(separator: " ")))
        }
        for (k, v) in extraAuthParams { items.append(.init(name: k, value: v)) }
        components.queryItems = items
        guard let authURL = components.url else { throw OAuthError.tokenExchangeFailed(message: "bad auth URL") }

        // Custom scheme = redirectURI's scheme (e.g. "inkling" or
        // "com.googleusercontent.apps.123-abc"). ASWebAuthenticationSession
        // dismisses itself when the system sees a redirect to that scheme.
        let scheme = URL(string: redirectURI)?.scheme ?? "inkling"

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: scheme
            ) { url, error in
                if let url { continuation.resume(returning: url); return }
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: OAuthError.userCancelled); return
                }
                continuation.resume(throwing: error ?? OAuthError.noAuthCode)
            }
            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = self
            session.start()
        }

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "code" })?
            .value else {
            throw OAuthError.noAuthCode
        }

        // Exchange the code for tokens.
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let bodyParams: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": codeVerifier,
        ]
        req.httpBody = Self.formEncode(bodyParams).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OAuthError.tokenExchangeFailed(message: body)
        }
        let envelope = try Self.decodeTokenEnvelope(data: data)
        let token = OAuthToken(
            accessToken: envelope.access_token,
            refreshToken: envelope.refresh_token,
            expiresAt: envelope.expires_in.map { Date().addingTimeInterval(TimeInterval($0)) },
            accountLabel: nil
        )
        OAuthTokenStore.save(token, for: kind)
        return token
    }

    /// Use the stored refresh token to mint a fresh access token. Throws if
    /// no refresh token is on file (caller should restart the sign-in flow).
    @discardableResult
    func refresh(
        kind: SyncProviderKind,
        clientID: String,
        tokenURL: URL
    ) async throws -> OAuthToken {
        guard let stored = OAuthTokenStore.load(kind),
              let refreshToken = stored.refreshToken else {
            throw OAuthError.tokenExchangeFailed(message: "no refresh token on file")
        }
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let bodyParams: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ]
        req.httpBody = Self.formEncode(bodyParams).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OAuthError.tokenExchangeFailed(message: body)
        }
        let envelope = try Self.decodeTokenEnvelope(data: data)
        let updated = OAuthToken(
            accessToken: envelope.access_token,
            // Some providers only return the refresh token on first issue;
            // keep the existing one if we didn't get a new one back.
            refreshToken: envelope.refresh_token ?? stored.refreshToken,
            expiresAt: envelope.expires_in.map { Date().addingTimeInterval(TimeInterval($0)) },
            accountLabel: stored.accountLabel
        )
        OAuthTokenStore.save(updated, for: kind)
        return updated
    }

    func signOut(_ kind: SyncProviderKind) {
        OAuthTokenStore.delete(kind)
    }

    // MARK: ASWebAuthenticationPresentationContextProviding

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Find the foremost key window. On Catalyst this surfaces a separate
        // browser window; on iPhone/iPad it's the in-app SFAuthSession sheet.
        if let window = MainActor.assumeIsolated({
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow }
        }) {
            return window
        }
        return ASPresentationAnchor()
    }

    // MARK: PKCE helpers

    private static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncodedString()
    }

    private static func formEncode(_ params: [String: String]) -> String {
        params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
    }

    private struct TokenEnvelope: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int?
        let token_type: String?
        let scope: String?
    }

    private static func decodeTokenEnvelope(data: Data) throws -> TokenEnvelope {
        do { return try JSONDecoder().decode(TokenEnvelope.self, from: data) }
        catch { throw OAuthError.decodingFailed }
    }
}

// MARK: Base64URL helper

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
