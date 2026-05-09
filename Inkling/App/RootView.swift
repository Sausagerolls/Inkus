import SwiftUI
import SwiftData

struct RootView: View {
    var body: some View {
        NavigationStack {
            EntryListView()
        }
    }
}

#Preview {
    RootView()
        .modelContainer(InklingPersistence.makeContainer(inMemory: true))
}
