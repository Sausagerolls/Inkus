import SwiftUI

struct WeeklyReflectionBanner: View {
    enum State { case offerGenerate, viewExisting, generating }

    let state: State
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.m) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(accent)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(accent.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if case .generating = state {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(Spacing.m)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.inkSecondary)
            )
        }
        .buttonStyle(.plain)
        .disabled(state == .generating)
    }

    private var title: String {
        switch state {
        case .offerGenerate: return "Your week is ready"
        case .viewExisting:  return "Last week, reflected"
        case .generating:    return "Reading your week…"
        }
    }

    private var subtitle: String {
        switch state {
        case .offerGenerate: return "Tap to generate your weekly reflection."
        case .viewExisting:  return "Tap to read it again."
        case .generating:    return "Generated entirely on your device."
        }
    }
}
