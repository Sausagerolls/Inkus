import SwiftUI
import SwiftData

/// Top-level "Talk" tab: list of saved chat threads + a new-chat button.
struct TalkView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<ChatThread> { $0.surfaceRaw == "talk" },
           sort: \ChatThread.updatedAt, order: .reverse)
    private var threads: [ChatThread]

    @State private var selectedThread: ChatThread?
    @State private var showingUnavailable = false

    var body: some View {
        Group {
            if threads.isEmpty {
                emptyState
            } else {
                threadList
            }
        }
        .navigationTitle("Talk")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    startNewThread()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New chat")
            }
        }
        .navigationDestination(item: $selectedThread) { thread in
            ChatThreadDetailView(thread: thread)
        }
        .alert("Apple Intelligence isn't available", isPresented: $showingUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(AIAvailability.unavailableReason ?? "Talk needs Apple Intelligence on this device.")
        }
    }

    // MARK: - Subviews

    private var threadList: some View {
        List {
            ForEach(threads) { thread in
                Button {
                    selectedThread = thread
                } label: {
                    threadRow(thread)
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: delete)
        }
        .listStyle(.plain)
    }

    private func threadRow(_ thread: ChatThread) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(thread.title)
                .font(.system(.headline, design: .serif))
                .lineLimit(1)
            HStack(spacing: Spacing.xs) {
                Text(thread.updatedAt.formatted(.relative(presentation: .numeric)))
                if let preview = lastMessagePreview(thread) {
                    Text("·")
                    Text(preview).lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(Color.inkAccent)
            Text("Talk to your journal")
                .font(.system(.title2, design: .serif))
            Text("A private, on-device conversation about what you've been writing. Nothing leaves this device.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
            Button {
                startNewThread()
            } label: {
                Label("Start a chat", systemImage: "square.and.pencil")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, Spacing.s + 2)
                    .background(Color.inkAccent, in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding(.top, Spacing.s)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Actions

    private func startNewThread() {
        guard AIAvailability.isAvailable else {
            showingUnavailable = true
            return
        }
        let thread = ChatThread(title: "New chat", surface: .talk)
        modelContext.insert(thread)
        try? modelContext.save()
        selectedThread = thread
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(threads[index])
        }
        try? modelContext.save()
    }

    private func lastMessagePreview(_ thread: ChatThread) -> String? {
        let messages = (thread.messages ?? []).sorted { $0.createdAt < $1.createdAt }
        return messages.last?.content
    }
}
