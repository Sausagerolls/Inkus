import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false

    @State private var page: Int = 0
    @State private var notificationStatus: NotificationScheduler.AuthorizationState = .notDetermined

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip", action: finish)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Spacing.l)
            .padding(.top, Spacing.m)

            TabView(selection: $page) {
                welcomePage.tag(0)
                privacyPage.tag(1)
                permissionsPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button(action: advance) {
                Text(page == 2 ? "Start writing" : "Continue")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.m)
                    .background(Capsule().fill(Color.inkAccent))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.l)
        }
        .task {
            notificationStatus = await NotificationScheduler.currentAuthorization()
        }
    }

    // MARK: Pages

    private var welcomePage: some View {
        OnboardingPage(
            symbol: "sparkles",
            title: "Welcome to Inkus",
            subtitle: "A quiet space for daily writing.",
            bodyText: "Each morning, a gentle prompt to help you start. Each Sunday, a reflection on your week. All written by you, kept on your phone."
        )
    }

    private var privacyPage: some View {
        OnboardingPage(
            symbol: "lock.shield",
            title: "Yours, and only yours",
            subtitle: "Everything stays on this device.",
            bodyText: "Your entries never leave your phone. Apple Intelligence runs the AI features locally — there's no server, no account, and no analytics watching what you write."
        )
    }

    private var permissionsPage: some View {
        VStack(spacing: Spacing.l) {
            Image(systemName: "bell.badge")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(Color.inkAccent)
            VStack(spacing: Spacing.s) {
                Text("Two quick choices")
                    .font(.system(.title2, design: .serif).weight(.semibold))
                Text("Both are optional. You can change them later in Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.l)

            VStack(spacing: Spacing.m) {
                permissionRow(
                    symbol: "bell.fill",
                    title: "Weekly reflection reminder",
                    detail: notificationDetail,
                    actionLabel: notificationActionLabel,
                    isPrimary: notificationStatus == .notDetermined,
                    action: handleNotifications
                )

                aiStatusRow
            }
            .padding(.horizontal, Spacing.l)

            Spacer()
        }
        .padding(.top, Spacing.xl)
    }

    private var notificationDetail: String {
        switch notificationStatus {
        case .authorized, .provisional: return "Sunday at 7pm. You can change the time in Settings."
        case .denied:                   return "Currently off. Enable from iOS Settings → Inkus → Notifications."
        case .ephemeral, .notDetermined:return "We'll ping you Sunday at 7pm with your week's reflection."
        }
    }

    private var notificationActionLabel: String {
        switch notificationStatus {
        case .authorized, .provisional: return "On"
        case .denied:                   return "Off"
        case .ephemeral, .notDetermined:return "Allow"
        }
    }

    private var aiStatusRow: some View {
        let isAvailable = AIAvailability.isAvailable
        return permissionRow(
            symbol: "sparkles",
            title: "Apple Intelligence",
            detail: isAvailable
                ? "Detected. Daily prompts and weekly reflections will be tailored on-device."
                : (AIAvailability.unavailableReason ?? "Not available — Inkus will use a curated prompt bank."),
            actionLabel: isAvailable ? "Ready" : "Off",
            isPrimary: false,
            action: { /* informational */ }
        )
    }

    private func permissionRow(
        symbol: String,
        title: String,
        detail: String,
        actionLabel: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.inkAccent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(action: action) {
                Text(actionLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, Spacing.m)
                    .padding(.vertical, Spacing.xs)
                    .background(Capsule().fill(isPrimary ? Color.inkAccent : Color.inkSecondary))
                    .foregroundStyle(isPrimary ? Color.white : Color.primary)
            }
            .buttonStyle(.plain)
            .disabled(!isPrimary)
        }
        .padding(Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.inkSecondary.opacity(0.5))
        )
    }

    // MARK: Actions

    private func advance() {
        if page < 2 {
            withAnimation { page += 1 }
        } else {
            finish()
        }
    }

    private func finish() {
        if notificationsEnabled {
            Task { await NotificationScheduler.scheduleWeeklyReflection() }
        }
        hasCompletedOnboarding = true
    }

    private func handleNotifications() {
        guard notificationStatus == .notDetermined else { return }
        Task {
            let granted = await NotificationScheduler.requestAuthorization()
            notificationsEnabled = granted
            notificationStatus = await NotificationScheduler.currentAuthorization()
        }
    }
}

struct OnboardingPage: View {
    let symbol: String
    let title: String
    let subtitle: String
    let bodyText: String

    var body: some View {
        VStack(spacing: Spacing.l) {
            Image(systemName: symbol)
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(Color.inkAccent)
            VStack(spacing: Spacing.s) {
                Text(title)
                    .font(.system(.largeTitle, design: .serif).weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Text(bodyText)
                .font(.callout)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.l)
            Spacer()
        }
        .padding(.top, Spacing.xl)
        .padding(.horizontal, Spacing.l)
    }
}
