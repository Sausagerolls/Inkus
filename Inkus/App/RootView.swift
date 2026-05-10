import SwiftUI
import SwiftData

struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        if hasCompletedOnboarding {
            TabView {
                NavigationStack {
                    EntryListView()
                }
                .tabItem {
                    Label("Journal", systemImage: "book.closed")
                }

                NavigationStack {
                    TalkView()
                }
                .tabItem {
                    Label("Talk", systemImage: "sparkles")
                }
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
