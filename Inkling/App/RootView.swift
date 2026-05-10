import SwiftUI
import SwiftData

struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        if hasCompletedOnboarding {
            NavigationStack {
                EntryListView()
            }
        } else {
            OnboardingView()
        }
    }
}

#Preview {
    RootView()
        .modelContainer(InkusPersistence.makeContainer(inMemory: true))
}
