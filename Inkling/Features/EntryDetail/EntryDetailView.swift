import SwiftUI
import SwiftData

struct EntryDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let entry: Entry

    @State private var isEditing = false
    @State private var sharedURL: URL?
    @State private var exportError: String?

    private let columns = [
        GridItem(.adaptive(minimum: 110), spacing: Spacing.s)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                header
                bodyText
                if !entry.photoFilenames.isEmpty { photosGrid }
                if !entry.tags.isEmpty { tagChips }
                Spacer(minLength: Spacing.xxl)
            }
            .padding(.horizontal, Spacing.l)
            .padding(.top, Spacing.m)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        share(asPDF: false)
                    } label: {
                        Label("Share Markdown", systemImage: "doc.text")
                    }
                    Button {
                        share(asPDF: true)
                    } label: {
                        Label("Share PDF", systemImage: "doc.richtext")
                    }
                    Divider()
                    Button("Edit") { isEditing = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Entry actions")
            }
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                EntryEditorView(entry: entry, isNewDraft: false)
            }
        }
        .sheet(item: Binding(
            get: { sharedURL.map(EntryShare.init) },
            set: { sharedURL = $0?.url }
        )) { wrapper in
            ShareSheet(items: [wrapper.url])
        }
    }

    private func share(asPDF: Bool) {
        do {
            let url = asPDF
                ? try ExportService.exportEntryPDF(entry)
                : try ExportService.exportEntryMarkdown(entry)
            sharedURL = url
        } catch {
            exportError = error.localizedDescription
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(entry.createdAt.formatted(.dateTime.weekday(.wide).month().day().year()))
                .font(.system(.title2, design: .serif))
                .foregroundStyle(.primary)
            HStack(spacing: Spacing.s) {
                Text(entry.createdAt.formatted(.dateTime.hour().minute()))
                if let mood = entry.moodEmoji, let label = entry.moodLabel {
                    Text("·")
                    Text("\(mood) \(label)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var bodyText: some View {
        Text(entry.body.isEmpty ? "Empty entry." : entry.body)
            .font(.system(.body, design: .serif))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    private var photosGrid: some View {
        LazyVGrid(columns: columns, spacing: Spacing.s) {
            ForEach(entry.photoFilenames, id: \.self) { filename in
                if let img = AttachmentStore.loadPhoto(filename: filename, for: entry.id) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private var tagChips: some View {
        FlowChips(tags: entry.tags)
    }
}

private struct EntryShare: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct FlowChips: View {
    let tags: [String]
    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(tags, id: \.self) { tag in
                Text("#\(tag)")
                    .font(.caption)
                    .padding(.horizontal, Spacing.s)
                    .padding(.vertical, Spacing.xs)
                    .background(Color.inkSecondary, in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
