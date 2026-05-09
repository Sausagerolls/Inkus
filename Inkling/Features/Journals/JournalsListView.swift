import SwiftUI
import SwiftData

struct JournalsListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Journal.sortOrder)
    private var journals: [Journal]

    @State private var editing: Journal?
    @State private var creating = false

    var body: some View {
        List {
            ForEach(journals) { journal in
                Button {
                    editing = journal
                } label: {
                    HStack(spacing: Spacing.m) {
                        Image(systemName: journal.iconName)
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color(hex: journal.accentColorHex)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(journal.name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            Text({
                                let n = journal.entries?.count ?? 0
                                return "\(n) \(n == 1 ? "entry" : "entries")"
                            }())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    if journals.count > 1 {
                        Button(role: .destructive) {
                            modelContext.delete(journal)
                            try? modelContext.save()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Journals")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    creating = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New journal")
            }
        }
        .sheet(item: $editing) { journal in
            JournalEditorView(editing: journal)
        }
        .sheet(isPresented: $creating) {
            JournalEditorView(editing: nil)
        }
    }
}
