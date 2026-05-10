import SwiftUI
import AuthenticationServices

struct AppleSignInSettingsView: View {
    @State private var service = AppleSignInService.shared
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                if service.isSignedIn {
                    if let name = service.displayName {
                        LabeledContent("Name", value: name)
                    }
                    if let email = service.email {
                        LabeledContent("Email", value: email)
                    }
                    Button(role: .destructive) {
                        service.signOut()
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } else {
                    SignInWithAppleButton(.signIn) { _ in
                        // We build the request ourselves inside AppleSignInService
                        // so the bridge can resolve the async continuation.
                    } onCompletion: { _ in
                        // No-op — see Task below.
                    }
                    .frame(height: 48)
                    .signInWithAppleButtonStyle(.black)
                    .overlay(
                        Color.white.opacity(0.001)
                            .onTapGesture { Task { await runSignIn() } }
                    )
                    if isWorking {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Opening Apple sign-in…")
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                        }
                    }
                }
            } header: {
                Text("Sign in with Apple")
            } footer: {
                if service.isSignedIn {
                    Text("To revoke access entirely, open iOS Settings → your name → Sign in with Apple → Inkus → Stop using Apple ID.")
                } else {
                    Text("Optional. Inkus has no account system. Signing in only stores your name and email on this device — used to greet you and stamp exports. Nothing is sent to a server.")
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Apple ID")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // If the user revoked access in iOS Settings, sign out locally too.
            await service.refreshCredentialState()
        }
    }

    private func runSignIn() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await service.signIn()
        } catch let nsError as NSError where nsError.domain == ASAuthorizationError.errorDomain
                                          && nsError.code == ASAuthorizationError.canceled.rawValue {
            // User cancelled — no error message.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
