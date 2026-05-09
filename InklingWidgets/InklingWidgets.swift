import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Shared snapshot (mirror of the main app's SharedPromptCache)

/// Local copy of the snapshot type written by the main app to the App Group
/// container. Kept identical in shape — if you change one, change both.
struct PromptSnapshot: Codable {
    var date: Date
    var promptText: String
    var followUps: [String]
    var sourceIsAI: Bool
    var accentHex: String

    static let placeholder = PromptSnapshot(
        date: .now,
        promptText: "What's something you noticed today that almost slipped past you?",
        followUps: [],
        sourceIsAI: false,
        accentHex: "#4F46E5"
    )

    static func loadFromAppGroup() -> PromptSnapshot? {
        guard let dir = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.giantmushroom.Inkling") else {
            return nil
        }
        let url = dir.appendingPathComponent("today_prompt.json")
        guard let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(PromptSnapshot.self, from: data) else {
            return nil
        }
        return snap
    }
}

// MARK: - Provider

struct DailyPromptProvider: TimelineProvider {
    func placeholder(in context: Context) -> PromptEntry {
        PromptEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (PromptEntry) -> Void) {
        let snap = PromptSnapshot.loadFromAppGroup() ?? .placeholder
        completion(PromptEntry(date: .now, snapshot: snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PromptEntry>) -> Void) {
        let snap = PromptSnapshot.loadFromAppGroup() ?? .placeholder
        let entry = PromptEntry(date: .now, snapshot: snap)

        // Refresh at the next local midnight so a new prompt picks up automatically.
        let cal = Calendar.current
        let tomorrow = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: .now) ?? .now)
        let timeline = Timeline(entries: [entry], policy: .after(tomorrow))
        completion(timeline)
    }
}

struct PromptEntry: TimelineEntry {
    let date: Date
    let snapshot: PromptSnapshot
}

// MARK: - Color helper

private func widgetColor(hex: String) -> Color {
    var trimmed = hex.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("#") { trimmed.removeFirst() }
    guard trimmed.count == 6, let value = UInt64(trimmed, radix: 16) else { return .indigo }
    let r = Double((value & 0xFF0000) >> 16) / 255.0
    let g = Double((value & 0x00FF00) >>  8) / 255.0
    let b = Double( value & 0x0000FF       ) / 255.0
    return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
}

// MARK: - Views

struct DailyPromptSmallView: View {
    let entry: PromptEntry

    var body: some View {
        let accent = widgetColor(hex: entry.snapshot.accentHex)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: entry.snapshot.sourceIsAI ? "sparkles" : "quote.opening")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accent)
                Text("Today")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(entry.snapshot.promptText)
                .font(.system(.callout, design: .serif))
                .foregroundStyle(.primary)
                .lineLimit(5)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
    }
}

struct DailyPromptMediumView: View {
    let entry: PromptEntry

    var body: some View {
        let accent = widgetColor(hex: entry.snapshot.accentHex)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: entry.snapshot.sourceIsAI ? "sparkles" : "quote.opening")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                Text(entry.snapshot.sourceIsAI ? "Today's prompt" : "A prompt for today")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(entry.snapshot.promptText)
                .font(.system(.body, design: .serif))
                .foregroundStyle(.primary)
                .lineLimit(4)
                .minimumScaleFactor(0.9)
            Spacer(minLength: 4)
            Button(intent: NewEntryIntent()) {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.pencil").font(.caption2.weight(.semibold))
                    Text("Start writing").font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(accent))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Widget

struct DailyPromptWidget: Widget {
    let kind: String = "DailyPromptWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyPromptProvider()) { entry in
            DailyPromptWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today's Prompt")
        .description("A gentle journaling prompt, refreshed each morning.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct DailyPromptWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: PromptEntry

    var body: some View {
        switch family {
        case .systemMedium: DailyPromptMediumView(entry: entry)
        default:            DailyPromptSmallView(entry: entry)
        }
    }
}

#Preview(as: .systemSmall) {
    DailyPromptWidget()
} timeline: {
    PromptEntry(date: .now, snapshot: .placeholder)
}

#Preview(as: .systemMedium) {
    DailyPromptWidget()
} timeline: {
    PromptEntry(date: .now, snapshot: .placeholder)
}
