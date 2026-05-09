import SwiftUI
import SwiftData

struct EntryListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Journal.sortOrder)
    private var journals: [Journal]

    @AppStorage("currentJournalID") private var currentJournalID: String = ""

    @State private var showingSwitcher = false
    @State private var showingNewJournal = false
    @State private var showingSearch = false
    @State private var showingSettings = false
    @State private var newDraft: Entry?
    @State private var draftPlaceholder: String? = nil
    @State private var todaysPrompt: DailyPrompt?
    @State private var lastWeekReflection: WeeklyReflection?
    @State private var shouldOfferReflection: Bool = false
    @State private var isGeneratingReflection: Bool = false
    @State private var presentedReflection: WeeklyReflection?

    private var currentJournal: Journal? {
        if let match = journals.first(where: { $0.id.uuidString == currentJournalID }) {
            return match
        }
        return journals.first
    }

    private var accent: Color {
        currentJournal.map { Color(hex: $0.accentColorHex) } ?? Color.inkAccent
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let journal = currentJournal {
                JournalEntriesList(
                    journal: journal,
                    promptCard: { promptCardView },
                    onDelete: delete,
                    onRefresh: { await refreshPrompt() }
                )
            } else {
                EmptyStateView(
                    symbol: "book.closed",
                    title: "No journals",
                    message: "Create one to start writing."
                )
            }
            newEntryButton
                .padding(Spacing.l)
        }
        .navigationTitle(currentJournal?.name ?? "Inkling")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingSwitcher = true
                } label: {
                    HStack(spacing: 4) {
                        if let j = currentJournal {
                            Image(systemName: j.iconName)
                                .foregroundStyle(Color(hex: j.accentColorHex))
                        }
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel("Switch journal")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Search")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
        .sheet(isPresented: $showingSwitcher) {
            JournalSwitcherView(
                selectedJournalID: $currentJournalID,
                onCreate: { showingNewJournal = true }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingNewJournal) {
            JournalEditorView(editing: nil) { created in
                currentJournalID = created.id.uuidString
            }
        }
        .sheet(isPresented: $showingSearch) {
            NavigationStack {
                SearchView(initialJournal: currentJournal)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(item: $newDraft) { draft in
            NavigationStack {
                EntryEditorView(
                    entry: draft,
                    isNewDraft: true,
                    placeholderOverride: draftPlaceholder
                )
            }
        }
        .sheet(item: $presentedReflection) { reflection in
            NavigationStack {
                WeeklyReflectionView(reflection: reflection)
            }
        }
        .task {
            if currentJournalID.isEmpty, let first = journals.first {
                currentJournalID = first.id.uuidString
            }
            await loadPromptIfNeeded()
            evaluateReflectionState()
        }
        .onChange(of: currentJournalID) { _, _ in
            evaluateReflectionState()
        }
    }

    @ViewBuilder
    private var promptCardView: some View {
        VStack(spacing: Spacing.s) {
            if shouldOfferReflection || lastWeekReflection != nil || isGeneratingReflection {
                WeeklyReflectionBanner(
                    state: bannerState,
                    accent: accent,
                    action: handleReflectionTap
                )
            }
            if let prompt = todaysPrompt {
                DailyPromptCard(prompt: prompt, accent: accent) {
                    startEntryFromPrompt(prompt)
                }
            }
        }
    }

    private var bannerState: WeeklyReflectionBanner.State {
        if isGeneratingReflection { return .generating }
        if lastWeekReflection != nil { return .viewExisting }
        return .offerGenerate
    }

    private func handleReflectionTap() {
        if let existing = lastWeekReflection {
            presentedReflection = existing
            return
        }
        guard let journal = currentJournal else { return }
        isGeneratingReflection = true
        Task { @MainActor in
            defer { isGeneratingReflection = false }
            let service = ReflectionService(context: modelContext)
            if let result = await service.generatePreviousWeekReflection(for: journal) {
                lastWeekReflection = result
                shouldOfferReflection = false
                presentedReflection = result
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
                .background(Circle().fill(accent))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        }
        .accessibilityLabel("New entry")
        .disabled(currentJournal == nil)
    }

    private func startNewEntry() {
        guard let journal = currentJournal else { return }
        let draft = Entry(body: "", journal: journal)
        modelContext.insert(draft)
        draftPlaceholder = nil
        newDraft = draft
    }

    private func startEntryFromPrompt(_ prompt: DailyPrompt) {
        guard let journal = currentJournal else { return }
        let draft = Entry(body: "", journal: journal)
        draft.sourcePromptID = prompt.id
        modelContext.insert(draft)
        prompt.wasUsed = true
        try? modelContext.save()
        draftPlaceholder = prompt.promptText
        newDraft = draft
    }

    private func delete(_ entry: Entry) {
        let id = entry.id
        modelContext.delete(entry)
        try? modelContext.save()
        AttachmentStore.deleteAllAttachments(for: id)
    }

    private func loadPromptIfNeeded() async {
        guard todaysPrompt == nil else { return }
        let service = DailyPromptService(context: modelContext)
        todaysPrompt = await service.todaysPrompt()
    }

    private func refreshPrompt() async {
        let service = DailyPromptService(context: modelContext)
        todaysPrompt = await service.regenerate()
    }

    private func evaluateReflectionState() {
        let service = ReflectionService(context: modelContext)
        let weekStart = ReflectionService.previousWeekStart()
        lastWeekReflection = service.existingReflection(for: weekStart, journal: currentJournal)
        shouldOfferReflection = (lastWeekReflection == nil) &&
            service.shouldOfferPreviousWeekReflection(for: currentJournal) &&
            AIAvailability.isAvailable
    }
}

/// Inner view scoped to a single journal — re-runs @Query when the journal changes
/// because the parent re-creates this view by id.
private struct JournalEntriesList<PromptCard: View>: View {
    let journal: Journal
    @ViewBuilder let promptCard: PromptCard
    let onDelete: (Entry) -> Void
    let onRefresh: () async -> Void

    @Query private var entries: [Entry]

    init(
        journal: Journal,
        @ViewBuilder promptCard: () -> PromptCard,
        onDelete: @escaping (Entry) -> Void,
        onRefresh: @escaping () async -> Void
    ) {
        self.journal = journal
        self.promptCard = promptCard()
        self.onDelete = onDelete
        self.onRefresh = onRefresh
        let journalID = journal.id
        _entries = Query(
            filter: #Predicate<Entry> { entry in
                entry.journal?.id == journalID
            },
            sort: [SortDescriptor(\Entry.createdAt, order: .reverse)]
        )
    }

    private var groupedByDay: [(date: Date, entries: [Entry])] {
        let calendar = Calendar.current
        let buckets = Dictionary(grouping: entries) { entry in
            calendar.startOfDay(for: entry.createdAt)
        }
        return buckets
            .map { (date: $0.key, entries: $0.value) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            Section {
                promptCard
                    .listRowInsets(EdgeInsets(top: Spacing.s, leading: Spacing.m,
                                              bottom: Spacing.s, trailing: Spacing.m))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            if entries.isEmpty {
                Section {
                    EmptyStateView(
                        symbol: journal.iconName,
                        title: "No entries in \(journal.name) yet",
                        message: "Tap the + button to start writing."
                    )
                    .frame(minHeight: 280)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            } else {
                ForEach(groupedByDay, id: \.date) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            NavigationLink(value: entry) {
                                EntryRowView(entry: entry)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    onDelete(entry)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    onDelete(entry)
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
        }
        .listStyle(.plain)
        .refreshable { await onRefresh() }
        .navigationDestination(for: Entry.self) { entry in
            EntryDetailView(entry: entry)
        }
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
