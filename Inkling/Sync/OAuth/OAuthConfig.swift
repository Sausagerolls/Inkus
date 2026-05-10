import Foundation

/// Per-provider OAuth knobs. Public client IDs only — no secrets, since Inkling
/// is a native app and the entire flow uses PKCE.
enum OAuthConfig {

    enum Dropbox {
        /// Set on first run from Info.plist `INKLING_DROPBOX_APP_KEY`. Empty
        /// when the user hasn't dropped their app key in yet.
        static var appKey: String {
            (Bundle.main.object(forInfoDictionaryKey: "INKLING_DROPBOX_APP_KEY") as? String) ?? ""
        }
        static let authorizationURL = URL(string: "https://www.dropbox.com/oauth2/authorize")!
        static let tokenURL         = URL(string: "https://api.dropboxapi.com/oauth2/token")!
        static let redirectURI      = "inkling://oauth-callback/dropbox"
        // Empty array → Dropbox falls back to whatever scopes the app was
        // configured with on the developer portal (files.content.* etc.).
        static let scopes: [String] = ["files.content.write", "files.content.read", "files.metadata.read", "files.metadata.write", "account_info.read"]
    }

    enum GoogleDrive {
        /// Set on first run from Info.plist `INKLING_GOOGLE_CLIENT_ID`. The
        /// reverse-DNS form (e.g. `123-abc.apps.googleusercontent.com`) — Google
        /// requires that exact string in the redirect URI as a custom scheme.
        static var clientID: String {
            (Bundle.main.object(forInfoDictionaryKey: "INKLING_GOOGLE_CLIENT_ID") as? String) ?? ""
        }
        static let authorizationURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        static let tokenURL         = URL(string: "https://oauth2.googleapis.com/token")!
        /// Per Google's iOS guidance: the redirect URI is the reverse-DNS of
        /// the client ID + a path. We compute it on demand.
        static var redirectURI: String {
            // Client IDs look like 123-abc.apps.googleusercontent.com — reverse
            // it to com.googleusercontent.apps.123-abc and append :/oauth-callback.
            let id = clientID
            guard !id.isEmpty else { return "" }
            let parts = id.split(separator: ".").reversed().joined(separator: ".")
            return "\(parts):/oauth-callback/google"
        }
        /// drive.file — per-app sandbox; Inkling can only see files it created
        /// itself, never the user's wider Drive. Best-practice scope.
        static let scopes: [String] = ["https://www.googleapis.com/auth/drive.file", "openid", "email"]
    }
}
