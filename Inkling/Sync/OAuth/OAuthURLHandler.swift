import Foundation
import SwiftUI

/// Captures the inkling://oauth-callback/* URL on cold-launch resumes (rare —
/// ASWebAuthenticationSession usually delivers the callback inline). Acts as a
/// safety net for the case where iOS opens the URL via the app's URL handlers
/// instead of the in-process auth session.
@MainActor
enum OAuthURLHandler {
    static func handle(_ url: URL) -> Bool {
        // Match either the `inkling://oauth-callback/*` form or the Google
        // reverse-DNS form `com.googleusercontent.apps.<id>:/oauth-callback/*`.
        let scheme = url.scheme ?? ""
        let path = url.path
        let isInklingScheme = scheme == "inkling"
        let isGoogleScheme = scheme.hasPrefix("com.googleusercontent.apps.")
        guard isInklingScheme || isGoogleScheme else { return false }
        guard path.hasPrefix("/oauth-callback") else { return false }
        // Currently a no-op. ASWebAuthenticationSession resolves the
        // continuation directly in OAuthHelper.signIn — this is a hook for
        // future deep links (e.g. opening the app at a specific entry).
        return true
    }
}
