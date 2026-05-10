import SwiftUI
import SwiftData

/// Small in-editor chat sheet pinned to a single draft. Knows only the
/// current entry's body; doesn't see the wider archive (privacy + focus).
///
/// One persisted thread per Entry (surface = .editor). Re-opens it next time
/// the user taps the assist button on the same draft.
struct EditorAssistantSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let entry: Entry

    @State private var thread: ChatThread?

    var body: some View {
        NavigationStack {
            Group {
                if !AIAvailability.isAvailable {
                    unavailable
                } else if let thread {
                    ChatThreadDetailView(thread: thread)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Assist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { ensureThread() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var unavailable: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Apple Intelligence isn't available")
                .font(.headline)
            Text(AIAvailability.unavailableReason ?? "")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func ensureThread() {
        if thread != nil { return }
        let entryID = entry.id
        let descriptor = FetchDescriptor<ChatThread>(
            predicate: #Predicate { $0.surfaceRaw == "editor" && $0.entry?.id == entryID },
            sortBy: [SortDescriptor(\ChatThread.updatedAt, order: .reverse)]
        )
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            thread = existing
        } else {
            let new = ChatThread(title: "Draft assistant", surface: .editor, entry: entry)
            modelContext.insert(new)
            try? modelContext.save()
            thread = new
        }
    }
}
