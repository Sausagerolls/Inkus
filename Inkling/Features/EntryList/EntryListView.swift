import SwiftUI
import SwiftData

struct EntryListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Entry.createdAt, order: .reverse)
    private var entries: [Entry]

    @Query(sort: \Journal.sortOrder)
    private var journals: [Journal]

    @State private var showingNewEntry = false
    @State private var newDraft: Entry?

    private var groupedByDay: [(date: Date, entries: [Entry])] {
        let calendar = Calendar.current
        let buckets = Dictionary(grouping: entries) { entry in
            calendar.startOfDay(for: entry.createdAt)
        }
        return buckets
            .map { (date: $0.key, entries: $0.value) }
            .sorted { $0.date > $1.date }
    }

    private var currentJournal: Journal? {
        journals.first
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            content
            newEntryButton
                .padding(Spacing.l)
        }
        .navigationTitle(currentJournal?.name ?? "Inkling")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $newDraft) { draft in
            NavigationStack {
                EntryEditorView(entry: draft, isNewDraft: true)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if entries.isEmpty {
            EmptyStateView(
                symbol: "book.closed",
                title: "No entries yet",
                message: "Tap the + button to start writing."
            )
        } else {
            List {
                ForEach(groupedByDay, id: \.date) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            NavigationLink(value: entry) {
                                EntryRowView(entry: entry)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    delete(entry)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    delete(entry)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Text(dayHeader(for: group.date))
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.plain)
            .navigationDestination(for: Entry.self) { entry in
                EntryDetailView(entry: entry)
            }
        }
    }

    private var newEntryButton: some View {
        Button {
            startNewEntry()
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle().fill(Color.inkAccent)
                )
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        }
        .accessibilityLabel("New entry")
    }

    private func startNewEntry() {
        let draft = Entry(body: "", journal: currentJournal)
        modelContext.insert(draft)
        newDraft = draft
    }

    private func delete(_ entry: Entry) {
        let id = entry.id
        modelContext.delete(entry)
        try? modelContext.save()
        AttachmentStore.deleteAllAttachments(for: id)
    }

    private func dayHeader(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let now = Date.now
        if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(.dateTime.weekday(.wide).month().day())
    }
}

#Preview {
    NavigationStack {
        EntryListView()
    }
    .modelContainer(InklingPersistence.makeContainer(inMemory: true))
}
