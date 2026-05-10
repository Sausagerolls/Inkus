import SwiftUI

struct ChatBubble: View {
    let role: ChatRole
    let content: String

    var body: some View {
        HStack {
            if role == .user { Spacer(minLength: Spacing.xl) }
            Text(content)
                .font(.system(.body, design: .serif))
                .foregroundStyle(role == .user ? .white : Color.inkInk)
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s + 2)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(role == .user ? Color.inkAccent : Color.inkSecondary)
                )
                .textSelection(.enabled)
            if role == .assistant { Spacer(minLength: Spacing.xl) }
        }
    }
}

/// Three-dot animated indicator shown while waiting on the model.
struct TypingIndicator: View {
    @State private var phase: Int = 0

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.inkSubtle)
                    .frame(width: 7, height: 7)
                    .opacity(phase == i ? 1 : 0.35)
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s + 2)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.inkSecondary)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, Spacing.xl)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(350))
                phase = (phase + 1) % 3
            }
        }
    }
}
