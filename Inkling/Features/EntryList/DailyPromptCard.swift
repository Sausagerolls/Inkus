import SwiftUI

struct DailyPromptCard: View {
    let prompt: DailyPrompt
    let accent: Color
    let onStartWriting: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: prompt.sourceIsAI ? "sparkles" : "quote.opening")
                    .font(.caption)
                    .foregroundStyle(accent)
                Text(prompt.sourceIsAI ? "Today's prompt" : "A prompt for today")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(prompt.promptText)
                .font(.system(.title3, design: .serif))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if !prompt.followUps.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(prompt.followUps, id: \.self) { follow in
                        HStack(alignment: .top, spacing: Spacing.s) {
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text(follow)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            Button(action: onStartWriting) {
                HStack(spacing: 4) {
                    Text("Start writing")
                        .fontWeight(.semibold)
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s)
                .background(Capsule().fill(accent))
            }
            .buttonStyle(.plain)
            .padding(.top, Spacing.xs)
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(accent.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accent.opacity(0.20), lineWidth: 1)
        )
    }
}
