import SwiftUI
import SwiftData

struct EntryDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let entry: Entry

    @State private var isEditing = false

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
                Button("Edit") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                EntryEditorView(entry: entry, isNewDraft: false)
            }
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
