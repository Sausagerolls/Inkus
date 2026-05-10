import SwiftUI

struct EntryRowView: View {
    let entry: Entry

    private var preview: String {
        let firstLine = entry.body
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? ""
        return firstLine.isEmpty ? "Untitled entry" : firstLine
    }

    private var timeString: String {
        entry.createdAt.formatted(.dateTime.hour().minute())
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.s) {
                    Text(timeString)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let mood = entry.moodEmoji {
                        Text(mood)
                            .font(.caption)
                    }
                    if !(entry.attachments ?? []).isEmpty {
                        Image(systemName: attachmentGlyph)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(preview)
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if !entry.tags.isEmpty {
                    HStack(spacing: Spacing.xs) {
                        ForEach(entry.tags.prefix(3), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Pick the glyph based on the dominant attachment kind so the row hints
    /// at what's inside without needing extra UI.
    private var attachmentGlyph: String {
        let kinds = (entry.attachments ?? []).map(\.kind)
        if kinds.contains(.scan)    { return "doc.viewfinder" }
        if kinds.contains(.drawing) { return "pencil.tip" }
        if kinds.contains(.audio)   { return "waveform" }
        return "photo"
    }

    private var accessibilityLabel: String {
        var parts: [String] = [timeString]
        if let mood = entry.moodLabel { parts.append("mood \(mood)") }
        parts.append(preview)
        let attachmentCount = (entry.attachments ?? []).count
        if attachmentCount > 0 {
            parts.append("\(attachmentCount) attachment\(attachmentCount == 1 ? "" : "s")")
        }
        if !entry.tags.isEmpty { parts.append("tags \(entry.tags.joined(separator: ", "))") }
        return parts.joined(separator: ", ")
    }
}
