import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("notificationHour") private var notificationHour: Int = 19
    @AppStorage("notificationMinute") private var notificationMinute: Int = 0
    @AppStorage("aiSuggestionsEnabled") private var aiSuggestionsEnabled = true

    @State private var notificationStatus: NotificationScheduler.AuthorizationState = .notDetermined
    @State private var notificationTime: Date = Calendar.current.date(
        bySettingHour: 19, minute: 0, second: 0, of: .now
    ) ?? .now

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                journalsSection
                notificationsSection
                aiSection
                privacySection
                exportSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                notificationStatus = await NotificationScheduler.currentAuthorization()
                notificationTime = Calendar.current.date(
                    bySettingHour: notificationHour,
                    minute: notificationMinute,
                    second: 0,
                    of: .now
                ) ?? .now
            }
            .onChange(of: notificationTime) { _, newTime in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newTime)
                notificationHour = comps.hour ?? 19
                notificationMinute = comps.minute ?? 0
                if notificationsEnabled {
                    Task { await NotificationScheduler.scheduleWeeklyReflection(
                        hour: notificationHour, minute: notificationMinute
                    ) }
                }
            }
            .onChange(of: notificationsEnabled) { _, isOn in
                Task {
                    if isOn {
                        if notificationStatus == .notDetermined {
                            await NotificationScheduler.requestAuthorization()
                            notificationStatus = await NotificationScheduler.currentAuthorization()
                        }
                        await NotificationScheduler.scheduleWeeklyReflection(
                            hour: notificationHour, minute: notificationMinute
                        )
                    } else {
                        NotificationScheduler.cancelWeeklyReflection()
                    }
                }
            }
        }
    }

    // MARK: Sections

    private var journalsSection: some View {
        Section("Journals") {
            NavigationLink {
                JournalsListView()
            } label: {
                Label("Manage journals", systemImage: "books.vertical")
            }
        }
    }

    private var notificationsSection: some View {
        Section {
            Toggle(isOn: $notificationsEnabled) {
                Label("Weekly reflection reminder", systemImage: "bell")
            }
            if notificationsEnabled {
                DatePicker(
                    "Sunday at",
                    selection: $notificationTime,
                    displayedComponents: .hourAndMinute
                )
            }
            if notificationStatus == .denied {
                Label("Notifications disabled in iOS Settings.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("A gentle ping each Sunday when your weekly reflection is ready.")
        }
    }

    private var aiSection: some View {
        Section {
            HStack(spacing: Spacing.s) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.inkAccent)
                Text("Apple Intelligence")
                Spacer()
                Text(AIAvailability.isAvailable ? "Ready" : "Off")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, Spacing.s)
                    .padding(.vertical, Spacing.xs)
                    .background(
                        Capsule().fill(
                            AIAvailability.isAvailable
                                ? Color.green.opacity(0.18)
                                : Color.orange.opacity(0.18)
                        )
                    )
                    .foregroundStyle(AIAvailability.isAvailable ? Color.green : Color.orange)
            }

            if let reason = AIAvailability.unavailableReason {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Toggle(isOn: $aiSuggestionsEnabled) {
                Label("Use AI suggestions", systemImage: "wand.and.stars")
            }
            .disabled(!AIAvailability.isAvailable)
        } header: {
            Text("AI")
        } footer: {
            Text("AI features run entirely on your device. Turning this off uses a curated bundled prompt bank.")
        }
    }

    private var privacySection: some View {
        Section("Privacy") {
            NavigationLink {
                PrivacyDetailView()
            } label: {
                Label("How your data is handled", systemImage: "lock.shield")
            }
            NavigationLink {
                CrisisResourcesView()
            } label: {
                Label("Crisis resources", systemImage: "heart.text.square")
            }
        }
    }

    private var exportSection: some View {
        Section("Export") {
            NavigationLink {
                ExportView()
            } label: {
                Label("Markdown / PDF", systemImage: "square.and.arrow.up")
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Label("Version", systemImage: "info.circle")
                Spacer()
                Text(appVersion)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Link(destination: URL(string: "mailto:hello@inkling.app")!) {
                Label("Contact", systemImage: "envelope")
            }
        }
    }
}
