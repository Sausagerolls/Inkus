import Foundation
import AuthenticationServices
import Security
import Observation
import UIKit

/// Token Sign-in-with-Apple. We do not have an Inkling account; this service
/// only persists the user's name + email locally so the app can greet them
/// and stamp export filenames. The Apple user identifier lives in the
/// Keychain so we can detect the same Apple ID across reinstalls; the
/// human-readable bits live in UserDefaults.
///
/// Why we offer this even though we have no account: Apple's Guideline 4.8
/// asks for Sign in with Apple as an equivalent option whenever third-party
/// sign-in is offered for *primary identity*. Inkling's third-party sign-ins
/// pick a storage destination, not identity, so SiwA isn't strictly required —
/// but offering it eliminates the reviewer guesswork.
@MainActor
@Observable
final class AppleSignInService: NSObject {

    static let shared = AppleSignInService()
    private override init() {
        super.init()
        // Pull the cached state on init.
        userIdentifier = Self.readUserIdentifier()
        displayName    = UserDefaults.standard.string(forKey: nameKey)
        email          = UserDefaults.standard.string(forKey: emailKey)
    }

    // Observable state surfaced to Settings.
    private(set) var userIdentifier: String?
    private(set) var displayName: String?
    private(set) var email: String?
    private(set) var lastError: String?

    var isSignedIn: Bool { userIdentifier != nil }

    private let nameKey   = "co.giantmushroom.inkling.appleSignIn.displayName"
    private let emailKey  = "co.giantmushroom.inkling.appleSignIn.email"
    private let kcService = "co.giantmushroom.inkling.appleSignIn.userIdentifier"

    // MARK: Public API

    /// Returns the suggested attribution string for stamping exports
    /// ("Jake Watts" if signed in, otherwise nil).
    var attributionLine: String? {
        if let displayName, !displayName.isEmpty { return displayName }
        if let email, !email.isEmpty { return email }
        return nil
    }

    func signIn() async throws {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        let credential = try await performRequest(request)
        guard let appleCredential = credential as? ASAuthorizationAppleIDCredential else {
            throw NSError(domain: "AppleSignInService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Unexpected credential type"])
        }
        applyCredential(appleCredential)
    }

    func signOut() {
        deleteUserIdentifier()
        UserDefaults.standard.removeObject(forKey: nameKey)
        UserDefaults.standard.removeObject(forKey: emailKey)
        userIdentifier = nil
        displayName = nil
        email = nil
        lastError = nil
    }

    /// Polls Apple for the credential's current state on launch. If the user
    /// has revoked authorisation in iOS Settings → Sign in with Apple → Inkling,
    /// we sign out locally too.
    func refreshCredentialState() async {
        guard let userIdentifier else { return }
        let provider = ASAuthorizationAppleIDProvider()
        let state: ASAuthorizationAppleIDProvider.CredentialState = await withCheckedContinuation { cont in
            provider.getCredentialState(forUserID: userIdentifier) { state, _ in
                cont.resume(returning: state)
            }
        }
        switch state {
        case .authorized:
            return
        case .revoked, .notFound:
            signOut()
        case .transferred:
            return
        @unknown default:
            return
        }
    }

    // MARK: Internals

    private func applyCredential(_ credential: ASAuthorizationAppleIDCredential) {
        userIdentifier = credential.user
        Self.writeUserIdentifier(credential.user)

        // Apple only returns name + email on the FIRST sign-in. Preserve any
        // values we already had from a previous sign-in.
        if let name = credential.fullName {
            let formatter = PersonNameComponentsFormatter()
            let formatted = formatter.string(from: name).trimmingCharacters(in: .whitespaces)
            if !formatted.isEmpty {
                displayName = formatted
                UserDefaults.standard.set(formatted, forKey: nameKey)
            }
        }
        if let providedEmail = credential.email, !providedEmail.isEmpty {
            email = providedEmail
            UserDefaults.standard.set(providedEmail, forKey: emailKey)
        }
        lastError = nil
    }

    /// Wraps ASAuthorizationController's delegate callback in async/await.
    private func performRequest(_ request: ASAuthorizationAppleIDRequest) async throws -> ASAuthorizationCredential {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ASAuthorizationCredential, Error>) in
            let controller = ASAuthorizationController(authorizationRequests: [request])
            let bridge = SignInBridge(continuation: cont)
            controller.delegate = bridge
            controller.presentationContextProvider = bridge
            // Hold the bridge alive until the callback fires.
            objc_setAssociatedObject(controller, &SignInBridge.holderKey, bridge, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            controller.performRequests()
        }
    }

    // MARK: Keychain (user identifier)

    nonisolated private static func writeUserIdentifier(_ id: String) {
        let service = "co.giantmushroom.inkling.appleSignIn.userIdentifier"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
        guard let data = id.data(using: .utf8) else { return }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    nonisolated private static func readUserIdentifier() -> String? {
        let service = "co.giantmushroom.inkling.appleSignIn.userIdentifier"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let id = String(data: data, encoding: .utf8) else { return nil }
        return id
    }

    nonisolated private func deleteUserIdentifier() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: kcService,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Delegate bridge for ASAuthorizationController. Holds the continuation and
/// resumes it from either callback. Strongly retained off the controller via
/// objc_setAssociatedObject so it doesn't deallocate before the callback.
private final class SignInBridge: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    static var holderKey: UInt8 = 0

    private let continuation: CheckedContinuation<ASAuthorizationCredential, Error>
    private var hasResumed = false

    init(continuation: CheckedContinuation<ASAuthorizationCredential, Error>) {
        self.continuation = continuation
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard !hasResumed else { return }
        hasResumed = true
        continuation.resume(returning: authorization.credential)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        guard !hasResumed else { return }
        hasResumed = true
        continuation.resume(throwing: error)
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
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
}
