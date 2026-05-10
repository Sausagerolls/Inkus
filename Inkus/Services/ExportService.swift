import Foundation
import SwiftUI
import PDFKit
import UIKit

/// Markdown and PDF export. Returns file URLs in a temporary directory that
/// the caller hands to ShareLink / UIActivityViewController.
@MainActor
enum ExportService {

    // MARK: Markdown

    static func markdown(for entry: Entry) -> String {
        var lines: [String] = []
        let title = entry.title?.isEmpty == false
            ? entry.title!
            : entry.createdAt.formatted(.dateTime.weekday(.wide).month().day().year())
        lines.append("# \(title)")
        lines.append("")
        lines.append("_\(entry.createdAt.formatted(.dateTime.weekday(.wide).month().day().year().hour().minute()))_")
        if let mood = entry.moodLabel {
            let prefix = entry.moodEmoji.map { "\($0) " } ?? ""
            lines.append("")
            lines.append("**Mood:** \(prefix)\(mood)")
        }
        if !entry.tags.isEmpty {
            lines.append("")
            lines.append("**Tags:** " + entry.tags.map { "#\($0)" }.joined(separator: " "))
        }
        if let weather = entry.weatherSummary {
            lines.append("")
            lines.append("**Weather:** \(weather)")
        }
        if let location = entry.locationName {
            lines.append("")
            lines.append("**Where:** \(location)")
        }
        lines.append("")
        lines.append("---")
        lines.append("")
        lines.append(entry.body)
        let attachments = entry.attachments ?? []
        if !attachments.isEmpty {
            let n = attachments.count
            lines.append("")
            lines.append("_(\(n) attachment\(n == 1 ? "" : "s") — see the app for the rendered images.)_")
        }
        return lines.joined(separator: "\n")
    }

    static func markdown(for journal: Journal, entries: [Entry]? = nil) -> String {
        let source = entries ?? journal.entries ?? []
        let sorted = source.sorted { $0.createdAt > $1.createdAt }
        var out: [String] = []
        out.append("# \(journal.name)")
        out.append("")
        out.append("_Exported \(Date.now.formatted(.dateTime.weekday(.wide).month().day().year()))_")
        out.append("")
        out.append("\(sorted.count) entr\(sorted.count == 1 ? "y" : "ies").")
        out.append("")
        for entry in sorted {
            out.append("\n\n")
            out.append(markdown(for: entry))
        }
        return out.joined(separator: "\n")
    }

    // MARK: File output

    private static func tempURL(filename: String) -> URL {
        FileManager.default
            .temporaryDirectory
            .appendingPathComponent("Inkus-Export-\(UUID().uuidString.prefix(8))", isDirectory: true)
            .appendingPathComponent(filename)
    }

    @discardableResult
    static func writeMarkdownFile(_ text: String, filename: String) throws -> URL {
        let url = tempURL(filename: filename)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func exportEntryMarkdown(_ entry: Entry) throws -> URL {
        let safeTitle = sanitisedFilename(
            entry.title ?? entry.createdAt.formatted(.dateTime.year().month().day())
        )
        return try writeMarkdownFile(markdown(for: entry), filename: "\(safeTitle).md")
    }

    static func exportJournalMarkdown(_ journal: Journal) throws -> URL {
        let safeName = sanitisedFilename(journal.name)
        return try writeMarkdownFile(markdown(for: journal), filename: "\(safeName).md")
    }

    // MARK: PDF

    static func exportEntryPDF(_ entry: Entry) throws -> URL {
        let view = ExportEntryPDFView(entry: entry)
            .frame(width: 612) // US Letter width in pt
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = .init(width: 612, height: nil)

        let url = tempURL(filename: "\(sanitisedFilename(entry.title ?? entry.createdAt.formatted(.dateTime.year().month().day()))).pdf")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try renderer.render { _, render in
            var box = CGRect(x: 0, y: 0, width: 612, height: 792)
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            render(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
        }
        return url
    }

    static func exportJournalPDF(_ journal: Journal) throws -> URL {
        let entries = (journal.entries ?? []).sorted { $0.createdAt > $1.createdAt }
        let view = ExportJournalPDFView(journal: journal, entries: entries)
            .frame(width: 612)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = .init(width: 612, height: nil)

        let url = tempURL(filename: "\(sanitisedFilename(journal.name)).pdf")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try renderer.render { _, render in
            var box = CGRect(x: 0, y: 0, width: 612, height: 792)
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            render(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
        }
        return url
    }

    // MARK: Helpers

    private static func sanitisedFilename(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_ "))
        let cleaned = trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let result = String(cleaned).replacingOccurrences(of: " ", with: "_")
        return result.isEmpty ? "Inkus-export" : result
    }
}

// MARK: SwiftUI views used to render PDF

struct ExportEntryPDFView: View {
    let entry: Entry

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(entry.createdAt.formatted(.dateTime.weekday(.wide).month().day().year()))
                .font(.system(.title, design: .serif).weight(.semibold))
            HStack(spacing: Spacing.s) {
                Text(entry.createdAt.formatted(.dateTime.hour().minute()))
                if let mood = entry.moodEmoji, let label = entry.moodLabel {
                    Text("·"); Text("\(mood) \(label)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            Text(entry.body)
                .font(.system(.body, design: .serif))
                .lineSpacing(4)

            if !entry.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(entry.tags, id: \.self) { tag in
                        Text("#\(tag)").font(.caption)
                    }
                }
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
            Text("Exported from Inkus — \(Date.now.formatted(.dateTime.month().day().year()))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
    }
}

struct ExportJournalPDFView: View {
    let journal: Journal
    let entries: [Entry]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.m) {
                Image(systemName: journal.iconName)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color(hex: journal.accentColorHex)))
                VStack(alignment: .leading) {
                    Text(journal.name)
                        .font(.system(.title, design: .serif).weight(.semibold))
                    Text("\(entries.count) entr\(entries.count == 1 ? "y" : "ies") · exported \(Date.now.formatted(.dateTime.month().day().year()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.createdAt.formatted(.dateTime.weekday(.wide).month().day()))
                        .font(.callout.weight(.semibold))
                    Text(entry.body)
                        .font(.system(.body, design: .serif))
                        .lineSpacing(2)
                    Divider().opacity(0.3)
                }
                .padding(.bottom, Spacing.s)
            }

            Spacer(minLength: 0)
            Text("Exported from Inkus — kept on device.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
    }
}
