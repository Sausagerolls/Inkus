import SwiftUI

struct SyncProviderSettingsView: View {
    @State private var store = SyncSettingsStore.shared
    @State private var status: SyncStatus = .idle
    @State private var isWorking = false
    @State private var dropboxToken: OAuthToken?
    @State private var driveToken: OAuthToken?

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $store.selectedKind) {
                    ForEach(SyncProviderKind.allCases) { kind in
                        Label {
                            Text(kind.displayName)
                        } icon: {
                            providerIcon(for: kind)
                        }
                        .tag(kind)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Cloud provider")
            } footer: {
                Text("Sync is opt-in. Inkus never holds your data — pick the provider you trust, or pick \"No sync\" and keep everything on this device.")
            }

            switch store.selectedKind {
            case .none:        noSyncSection
            case .iCloud:      iCloudSection
            case .nextcloud:   nextcloudSection
            case .dropbox:     dropboxSection
            case .googleDrive: driveSection
            }
        }
        .navigationTitle("Sync")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            dropboxToken = OAuthTokenStore.load(.dropbox)
            driveToken = OAuthTokenStore.load(.googleDrive)
        }
        .onChange(of: store.selectedKind) { _, _ in
            // Reset transient state so a stale "OK" or error from the previous
            // provider doesn't bleed into the new section.
            status = .idle
            isWorking = false
        }
    }

    // MARK: Provider icon helper

    @ViewBuilder
    private func providerIcon(for kind: SyncProviderKind) -> some View {
        if let asset = kind.assetName {
            Image(asset).resizable().scaledToFit().frame(width: 22, height: 22)
        } else {
            Image(systemName: kind.symbol)
        }
    }

    // MARK: Sections

    private var noSyncSection: some View {
        Section {
            Label("Local only", systemImage: "iphone")
            Text("Entries and attachments stay on this device. You can switch to a sync provider later without losing anything.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var iCloudSection: some View {
        Section {
            HStack {
                Label("Status", systemImage: "icloud")
                Spacer()
                Text(InkusPersistence.activeBackingStore == .cloudKit ? "On" : "Off")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, Spacing.s)
                    .padding(.vertical, Spacing.xs)
                    .background(
                        Capsule().fill(
                            InkusPersistence.activeBackingStore == .cloudKit
                                ? Color.green.opacity(0.18)
                                : Color.orange.opacity(0.18)
                        )
                    )
                    .foregroundStyle(InkusPersistence.activeBackingStore == .cloudKit ? Color.green : Color.orange)
            }
            Text("iCloud sync is system-managed. Toggle Inkus under Settings → [Your Name] → iCloud → See All → Inkus.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("iCloud")
        }
    }

    private var nextcloudSection: some View {
        Section {
            TextField("Server URL", text: $store.nextcloudURL, prompt: Text("https://cloud.example.com"))
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
            TextField("Username", text: $store.nextcloudUser)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("App password", text: $store.nextcloudPassword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button {
                Task { await testNextcloud() }
            } label: {
                HStack {
                    Label("Test connection", systemImage: "checkmark.shield")
                    Spacer()
                    if isWorking { ProgressView().controlSize(.small) }
                }
            }
            .disabled(isWorking || store.nextcloudURL.isEmpty || store.nextcloudUser.isEmpty || store.nextcloudPassword.isEmpty)

            statusRow
        } header: {
            Text("Nextcloud")
        } footer: {
            Text("Generate an app password in Nextcloud under Settings → Security → \"Generate app password.\" Inkus stores it in the iOS Keychain. Files sync to a folder named \"Inkus\" in your account home.")
        }
    }

    private var dropboxSection: some View {
        Section {
            if let token = dropboxToken {
                HStack {
                    Label("Signed in", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                    Spacer()
                    if let label = token.accountLabel {
                        Text(label).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Button {
                    Task { await testProvider(.dropbox) }
                } label: {
                    HStack {
                        Label("Test connection", systemImage: "checkmark.shield")
                        Spacer()
                        if isWorking { ProgressView().controlSize(.small) }
                    }
                }
                .disabled(isWorking)
                Button(role: .destructive) {
                    OAuthHelper.shared.signOut(.dropbox)
                    dropboxToken = nil
                    status = .idle
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } else {
                Button {
                    Task { await signInDropbox() }
                } label: {
                    HStack {
                        Label("Sign in to Dropbox", systemImage: "person.crop.circle.badge.plus")
                        Spacer()
                        if isWorking { ProgressView().controlSize(.small) }
                    }
                }
                .disabled(isWorking)
            }
            statusRow
        } header: {
            Text("Dropbox")
        } footer: {
            if OAuthConfig.Dropbox.appKey.isEmpty {
                Text("Set INKLING_DROPBOX_APP_KEY in the build before signing in. See README for the setup walkthrough.")
                    .foregroundStyle(.orange)
            } else {
                Text("Files sync to /Inkus in your Dropbox. Inkus only sees files inside that folder.")
            }
        }
    }

    private var driveSection: some View {
        Section {
            if let token = driveToken {
                HStack {
                    Label("Signed in", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                    Spacer()
                    if let label = token.accountLabel {
                        Text(label).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Button {
                    Task { await testProvider(.googleDrive) }
                } label: {
                    HStack {
                        Label("Test connection", systemImage: "checkmark.shield")
                        Spacer()
                        if isWorking { ProgressView().controlSize(.small) }
                    }
                }
                .disabled(isWorking)
                Button(role: .destructive) {
                    OAuthHelper.shared.signOut(.googleDrive)
                    driveToken = nil
                    status = .idle
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } else {
                Button {
                    Task { await signInGoogle() }
                } label: {
                    HStack {
                        Label("Sign in with Google", systemImage: "person.crop.circle.badge.plus")
                        Spacer()
                        if isWorking { ProgressView().controlSize(.small) }
                    }
                }
                .disabled(isWorking)
            }
            statusRow
        } header: {
            Text("Google Drive")
        } footer: {
            if OAuthConfig.GoogleDrive.clientID.isEmpty {
                Text("Set INKLING_GOOGLE_CLIENT_ID in the build before signing in. See README for the setup walkthrough.")
                    .foregroundStyle(.orange)
            } else {
                Text("Inkus uses the drive.file scope — it can only read and write files it created itself, never your wider Drive.")
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch status {
        case .idle:
            EmptyView()
        case .syncing:
            HStack {
                ProgressView().controlSize(.small)
                Text("Working…").foregroundStyle(.secondary).font(.footnote)
            }
        case .ok(let at):
            Label("OK \(at.formatted(.relative(presentation: .numeric)))", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
                .font(.footnote)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .font(.footnote)
        }
    }

    // MARK: Actions

    private func signInDropbox() async {
        isWorking = true; status = .syncing
        defer { isWorking = false }
        do {
            let token = try await OAuthHelper.shared.signIn(
                kind: .dropbox,
                clientID: OAuthConfig.Dropbox.appKey,
                authorizationURL: OAuthConfig.Dropbox.authorizationURL,
                tokenURL: OAuthConfig.Dropbox.tokenURL,
                redirectURI: OAuthConfig.Dropbox.redirectURI,
                scopes: OAuthConfig.Dropbox.scopes,
                extraAuthParams: ["token_access_type": "offline"] // request refresh token
            )
            dropboxToken = token
            await testProvider(.dropbox)
        } catch {
            status = .error(message: humanise(error))
        }
    }

    private func signInGoogle() async {
        isWorking = true; status = .syncing
        defer { isWorking = false }
        do {
            let token = try await OAuthHelper.shared.signIn(
                kind: .googleDrive,
                clientID: OAuthConfig.GoogleDrive.clientID,
                authorizationURL: OAuthConfig.GoogleDrive.authorizationURL,
                tokenURL: OAuthConfig.GoogleDrive.tokenURL,
                redirectURI: OAuthConfig.GoogleDrive.redirectURI,
                scopes: OAuthConfig.GoogleDrive.scopes,
                extraAuthParams: ["access_type": "offline", "prompt": "consent"]
            )
            driveToken = token
            await testProvider(.googleDrive)
        } catch {
            status = .error(message: humanise(error))
        }
    }

    private func testNextcloud() async {
        isWorking = true; status = .syncing
        defer { isWorking = false }
        let provider = NextcloudProvider(credentials: store.nextcloudCredentials)
        do {
            try await provider.validateConfiguration()
            status = .ok(at: .now)
        } catch {
            status = .error(message: humanise(error))
        }
    }

    private func testProvider(_ kind: SyncProviderKind) async {
        isWorking = true; status = .syncing
        defer { isWorking = false }
        do {
            switch kind {
            case .dropbox:
                try await DropboxProvider().validateConfiguration()
                dropboxToken = OAuthTokenStore.load(.dropbox)
            case .googleDrive:
                try await GoogleDriveProvider().validateConfiguration()
                driveToken = OAuthTokenStore.load(.googleDrive)
            default:
                break
            }
            status = .ok(at: .now)
        } catch {
            status = .error(message: humanise(error))
        }
    }

    private func humanise(_ error: any Error) -> String {
        if let providerError = error as? SyncProviderError {
            switch providerError {
            case .notImplemented:    return "This provider isn't ready yet."
            case .notConfigured:     return "Sign in first."
            case .http(let s, let body):
                if let body, !body.isEmpty { return "HTTP \(s): \(body.prefix(200))" }
                return "Server returned HTTP \(s)."
            case .decoding(let m):   return m
            case .underlying(let e): return e.localizedDescription
            }
        }
        if let oauthError = error as? OAuthHelper.OAuthError {
            return oauthError.errorDescription ?? "Sign-in failed."
        }
        return error.localizedDescription
    }
}
