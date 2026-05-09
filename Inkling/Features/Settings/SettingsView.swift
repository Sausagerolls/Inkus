import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("notificationHour") private var notificationHour: Int = 19
    @AppStorage("notificationMinute") private var notificationMinute: Int = 0
    @AppStorage("aiSuggestionsEnabled") private var aiSuggestionsEnabled = true
    @AppStorage("currentJournalID") private var currentJournalID: String = ""

    @Query(sort: \Journal.sortOrder) private var allJournals: [Journal]
    @State private var generatedReflection: WeeklyReflection?
    @State private var isGeneratingReflection = false
    @State private var reflectionError: String?

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
                syncSection
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
            .sheet(item: $generatedReflection) { reflection in
                NavigationStack {
                    WeeklyReflectionView(reflection: reflection)
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

            Button {
                generateReflectionNow()
            } label: {
                HStack {
                    Label("Generate this week's reflection", systemImage: "sparkles.rectangle.stack")
                    Spacer()
                    if isGeneratingReflection {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(!AIAvailability.isAvailable || isGeneratingReflection)

            if let message = reflectionError {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("AI")
        } footer: {
            Text("AI features run entirely on your device. Turning this off uses a curated bundled prompt bank. \"Generate this week's reflection\" uses entries from the current Mon–Sun.")
        }
    }

    private var currentJournal: Journal? {
        allJournals.first { $0.id.uuidString == currentJournalID } ?? allJournals.first
    }

    private func generateReflectionNow() {
        reflectionError = nil
        isGeneratingReflection = true
        Task { @MainActor in
            defer { isGeneratingReflection = false }
            let service = ReflectionService(context: modelContext)
            if let result = await service.generateCurrentWeekReflection(for: currentJournal) {
                generatedReflection = result
            } else {
                reflectionError = "No entries this week yet, or generation failed."
            }
        }
    }

    private var syncSection: some View {
        Section {
            HStack(spacing: Spacing.s) {
                Image(systemName: "icloud")
                    .foregroundStyle(Color.inkAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("iCloud sync")
                        .font(.callout.weight(.medium))
                    Text(syncStatusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(syncStatusBadge)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, Spacing.s)
                    .padding(.vertical, Spacing.xs)
                    .background(Capsule().fill(syncStatusBadgeBackground))
                    .foregroundStyle(syncStatusBadgeForeground)
            }
            if case .localFallback(let reason) = InklingPersistence.activeBackingStore {
                Text("CloudKit error: \(reason)")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("To enable or disable sync:")
                    .font(.footnote.weight(.medium))
                Text("Settings → your name at the top → iCloud → See All → Inkling")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, Spacing.xs)
        } header: {
            Text("Sync")
        } footer: {
            Text("Text entries, mood, and tags sync via your private iCloud database. Photos stay on this device for now (sync coming in a future update). Inkling will only show in the iCloud apps list after you've written an entry while signed in to iCloud.")
        }
    }

    private var syncStatusBadge: String {
        switch InklingPersistence.activeBackingStore {
        case .cloudKit:        return "On"
        case .local:           return "Local"
        case .localFallback:   return "Off"
        case .inMemory:        return "Memory"
        }
    }

    private var syncStatusDetail: String {
        switch InklingPersistence.activeBackingStore {
        case .cloudKit:        return "Active. Entries sync through your iCloud account."
        case .local:           return "Local-only store."
        case .localFallback:   return "CloudKit unavailable — using local storage."
        case .inMemory:        return "In-memory (preview/test)."
        }
    }

    private var syncStatusBadgeBackground: Color {
        switch InklingPersistence.activeBackingStore {
        case .cloudKit:      return Color.green.opacity(0.18)
        case .localFallback: return Color.orange.opacity(0.18)
        default:             return Color.inkSecondary
        }
    }

    private var syncStatusBadgeForeground: Color {
        switch InklingPersistence.activeBackingStore {
        case .cloudKit:      return Color.green
        case .localFallback: return Color.orange
        default:             return Color.primary
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
            Link(destination: URL(string: "mailto:contact@giantmushroom.studio")!) {
                Label("Contact", systemImage: "envelope")
            }
        }
    }
}
