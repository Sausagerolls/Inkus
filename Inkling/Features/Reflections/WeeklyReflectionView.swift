import SwiftUI
import SwiftData

struct WeeklyReflectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let reflection: WeeklyReflection

    private var weekRangeString: String {
        let start = reflection.weekStartDate
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
        let f = Date.FormatStyle.dateTime.month(.abbreviated).day()
        return "\(start.formatted(f)) – \(end.formatted(f))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Color.inkAccent)
                        Text("Week of \(weekRangeString)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Text("Your week, reflected")
                        .font(.system(.largeTitle, design: .serif))
                        .foregroundStyle(.primary)
                }

                Text(reflection.summary)
                    .font(.system(.body, design: .serif))
                    .lineSpacing(4)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                if !reflection.themes.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text("Themes")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: Spacing.xs) {
                            ForEach(reflection.themes, id: \.self) { theme in
                                Text(theme)
                                    .font(.caption)
                                    .padding(.horizontal, Spacing.s)
                                    .padding(.vertical, Spacing.xs)
                                    .background(Color.inkSecondary, in: Capsule())
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("Mood arc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(reflection.moodArcDescription)
                        .font(.callout)
                        .foregroundStyle(.primary)
                }

                Text("Generated on \(reflection.generatedAt.formatted(.dateTime.month().day().hour().minute())) — never left your device.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, Spacing.m)
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.m)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }
}
