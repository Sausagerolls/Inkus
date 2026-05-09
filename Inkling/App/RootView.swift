import SwiftUI

struct RootView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Inkling")
                .font(.system(.largeTitle, design: .serif))
            Text("Phase 0 — placeholder")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    RootView()
}
