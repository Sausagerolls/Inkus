import SwiftUI
import SwiftData

struct SearchView: View {
    enum Scope: Hashable { case currentJournal, allJournals }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let initialJournal: Journal?

    @State private var query: String = ""
    @State private var scope: Scope
    @State private var moodFilter: String? = nil
    @State private var tagFilter: String? = nil

    @Query(sort: \Entry.createdAt, order: .reverse)
    private var allEntries: [Entry]

    init(initialJournal: Journal?) {
        self.initialJournal = initialJournal
        _scope = State(initialValue: initialJournal == nil ? .allJournals : .currentJournal)
    }

    private var availableMoods: [String] {
        let moods = Set(allEntries.compactMap(\.moodLabel))
        return moods.sorted()
    }

    private var availableTags: [String] {
        let tags = Set(allEntries.flatMap(\.tags))
        return tags.sorted()
    }

    private var results: [Entry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allEntries.filter { entry in
            if scope == .currentJournal, let target = initialJournal {
                guard entry.journal?.id == target.id else { return false }
            }
            if let mood = moodFilter, entry.moodLabel != mood { return false }
            if let tag = tagFilter, !entry.tags.contains(tag) { return false }
            if q.isEmpty { return true }
            if entry.body.localizedStandardContains(q) { return true }
            if let title = entry.title, title.localizedStandardContains(q) { return true }
            return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterStrip
            Divider()
            resultsList
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .searchable(text: $query, prompt: "Search entries")
    }

    @ViewBuilder
    private var filterStrip: some View {
        VStack(spacing: Spacing.s) {
            if initialJournal != nil {
                Picker("Scope", selection: $scope) {
                    Text("This journal").tag(Scope.currentJournal)
                    Text("All journals").tag(Scope.allJournals)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Spacing.m)
            }

            if !availableMoods.isEmpty || !availableTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.s) {
                        ForEach(availableMoods, id: \.self) { mood in
                            FilterChip(
                                label: mood,
                                symbol: "face.smiling",
                                isOn: moodFilter == mood
                            ) {
                                moodFilter = (moodFilter == mood) ? nil : mood
                            }
                        }
                        ForEach(availableTags, id: \.self) { tag in
                            FilterChip(
                                label: "#\(tag)",
                                symbol: "tag",
                                isOn: tagFilter == tag
                            ) {
                                tagFilter = (tagFilter == tag) ? nil : tag
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.m)
                }
            }
        }
        .padding(.vertical, Spacing.s)
    }

    @ViewBuilder
    private var resultsList: some View {
        if results.isEmpty {
            EmptyStateView(
                symbol: "magnifyingglass",
                title: query.isEmpty && moodFilter == nil && tagFilter == nil
                    ? "Search your entries"
                    : "No matches",
                message: query.isEmpty && moodFilter == nil && tagFilter == nil
                    ? "Type a word, or pick a mood or tag chip."
                    : "Try a different word or clear a filter."
            )
        } else {
            List(results) { entry in
                NavigationLink(value: entry) {
                    EntryRowView(entry: entry)
                }
            }
            .listStyle(.plain)
            .navigationDestination(for: Entry.self) { entry in
                EntryDetailView(entry: entry)
            }
        }
    }
}

private struct FilterChip: View {
    let label: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.caption2)
                Text(label).font(.caption.weight(.medium))
            }
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)
            .background(
                Capsule().fill(isOn ? Color.inkAccent : Color.inkSecondary)
            )
            .foregroundStyle(isOn ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
