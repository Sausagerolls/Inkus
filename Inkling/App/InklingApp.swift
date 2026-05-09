import SwiftUI
import SwiftData

@main
struct InklingApp: App {
    let container: ModelContainer = InklingPersistence.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
