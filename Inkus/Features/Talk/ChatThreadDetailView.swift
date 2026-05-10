import SwiftUI
import SwiftData

struct ChatThreadDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let thread: ChatThread

    @Query private var allEntries: [Entry]
    @State private var draft: String = ""
    @State private var isReplying: Bool = false
    @State private var sendError: String?
    @State private var service: JournalChatService?
    @FocusState private var inputFocused: Bool

    /// Stable ordering for the SwiftData relationship.
    private var orderedMessages: [ChatMessage] {
        (thread.messages ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            messagesList
            Divider()
            inputBar
        }
        .navigationTitle(thread.title)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.inkBackground)
        .alert("Couldn't reach Apple Intelligence", isPresented: errorBinding) {
            Button("OK", role: .cancel) { sendError = nil }
        } message: {
            Text(sendError ?? "")
        }
        .task {
            await ensureService()
        }
    }

    // MARK: - Subviews

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.s) {
                    if orderedMessages.isEmpty {
                        EmptyStatePrompt()
                            .padding(.top, Spacing.xxl)
                    }
                    ForEach(orderedMessages) { msg in
                        ChatBubble(role: msg.role, content: msg.content)
                            .id(msg.id)
                    }
                    if isReplying {
                        TypingIndicator().id("typing")
                    }
                }
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.m)
            }
            .onChange(of: orderedMessages.count) { _, _ in
                if let last = orderedMessages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: isReplying) { _, replying in
                if replying { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } }
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: Spacing.s) {
            TextField("Write a message…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.inkSecondary)
                )
                .focused($inputFocused)

            Button {
                Task { await send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? Color.inkAccent : Color.inkSubtle)
            }
            .disabled(!canSend)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
    }

    // MARK: - Actions

    private var canSend: Bool {
        !isReplying && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { sendError != nil }, set: { if !$0 { sendError = nil } })
    }

    private func ensureService() async {
        guard service == nil else { return }
        let digest: String
        switch thread.surface {
        case .talk:
            digest = ChatContextBuilder.recentDigest(from: allEntries)
        case .editor:
            if let entry = thread.entry {
                digest = ChatContextBuilder.draftDigest(from: entry)
            } else {
                digest = ""
            }
        }
        service = JournalChatService(surface: thread.surface, recentDigest: digest)
        // Note: we deliberately don't replay prior turns into the model.
        // LanguageModelSession can't persist its hidden state across app
        // launches anyway, and replaying user turns blindly causes the
        // model to re-generate (and remember) fresh confabulations every
        // time the thread is re-opened. The visible chat history is for
        // the writer; the model's memory is only the current session.
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let svc = service else { return }
        draft = ""
        isReplying = true

        let userMsg = ChatMessage(role: .user, content: text, thread: thread)
        modelContext.insert(userMsg)
        thread.updatedAt = .now
        if thread.title == "New chat" { thread.title = Self.titleFromFirstTurn(text) }
        try? modelContext.save()

        do {
            let reply = try await svc.reply(to: text)
            let assistantMsg = ChatMessage(role: .assistant, content: reply, thread: thread)
            modelContext.insert(assistantMsg)
            thread.updatedAt = .now
            try? modelContext.save()
        } catch {
            sendError = AIAvailability.unavailableReason ?? error.localizedDescription
        }
        isReplying = false
    }

    private static func titleFromFirstTurn(_ text: String) -> String {
        let trimmed = text.replacingOccurrences(of: "\n", with: " ")
        let words = trimmed.split(separator: " ").prefix(6).joined(separator: " ")
        return words.isEmpty ? "Chat" : String(words)
    }
}

private struct EmptyStatePrompt: View {
    var body: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(Color.inkAccent)
            Text("Talk to your journal")
                .font(.system(.title3, design: .serif))
            Text("Ask about patterns, recurring themes, or anything you've been turning over. Stays on this device.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.l)
        }
        .frame(maxWidth: .infinity)
    }
}
