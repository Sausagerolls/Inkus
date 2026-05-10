import SwiftUI

struct SyncProviderSettingsView: View {
    @State private var store = SyncSettingsStore.shared
    @State private var status: SyncStatus = .idle
    @State private var isTesting = false

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $store.selectedKind) {
                    ForEach(SyncProviderKind.allCases) { kind in
                        Label(kind.displayName, systemImage: kind.symbol).tag(kind)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Cloud provider")
            } footer: {
                providerFooter
            }

            switch store.selectedKind {
            case .iCloud:      iCloudSection
            case .nextcloud:   nextcloudSection
            case .dropbox, .googleDrive: comingSoonSection
            }
        }
        .navigationTitle("Sync")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Sections

    private var iCloudSection: some View {
        Section {
            HStack {
                Label("Status", systemImage: "icloud")
                Spacer()
                Text(InklingPersistence.activeBackingStore == .cloudKit ? "On" : "Off")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, Spacing.s)
                    .padding(.vertical, Spacing.xs)
                    .background(
                        Capsule().fill(
                            InklingPersistence.activeBackingStore == .cloudKit
                                ? Color.green.opacity(0.18)
                                : Color.orange.opacity(0.18)
                        )
                    )
                    .foregroundStyle(InklingPersistence.activeBackingStore == .cloudKit ? Color.green : Color.orange)
            }
            Text("iCloud sync is system-managed. Toggle Inkling under Settings → [Your Name] → iCloud → See All → Inkling.")
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
                    if isTesting { ProgressView().controlSize(.small) }
                }
            }
            .disabled(isTesting || store.nextcloudURL.isEmpty || store.nextcloudUser.isEmpty || store.nextcloudPassword.isEmpty)

            statusRow
        } header: {
            Text("Nextcloud")
        } footer: {
            Text("Generate an app password in Nextcloud under Settings → Security → \"Generate app password.\" Inkling stores it in the iOS Keychain. Files sync to a folder named \"Inkling\" in your account home.")
        }
    }

    private var comingSoonSection: some View {
        Section {
            Label("Coming soon", systemImage: "hourglass")
                .foregroundStyle(.secondary)
            Text("OAuth sign-in for \(store.selectedKind.displayName) ships in a future update. For now, choose iCloud or Nextcloud.")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
            Label("Last test OK \(at.formatted(.relative(presentation: .numeric)))", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
                .font(.footnote)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .font(.footnote)
        }
    }

    private var providerFooter: some View {
        Text("Sync is opt-in. iCloud syncs through your Apple account; Nextcloud through a server you control. Dropbox and Google Drive integration is coming. Whatever you pick, Inkling never holds the data — it lives on your device and (optionally) in your chosen provider.")
    }

    // MARK: Actions

    private func testNextcloud() async {
        isTesting = true; status = .syncing
        defer { isTesting = false }
        let provider = NextcloudProvider(credentials: store.nextcloudCredentials)
        do {
            try await provider.validateConfiguration()
            status = .ok(at: .now)
        } catch {
            status = .error(message: humanise(error))
        }
    }

    private func humanise(_ error: any Error) -> String {
        if let providerError = error as? SyncProviderError {
            switch providerError {
            case .notImplemented:    return "This provider isn't ready yet."
            case .notConfigured:     return "Fill in the server, username, and app password."
            case .http(let s, _):    return "Server returned HTTP \(s)."
            case .decoding(let m):   return m
            case .underlying(let e): return e.localizedDescription
            }
        }
        return error.localizedDescription
    }
}
