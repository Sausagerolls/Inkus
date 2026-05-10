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
    @AppStorage("entryViewMode") private var viewModeRaw: String = ViewMode.list.rawValue

    private enum ViewMode: String, CaseIterable, Identifiable {
        case list, calendar
        var id: String { rawValue }
        var symbol: String { self == .list ? "list.bullet" : "calendar" }
    }
    private var viewMode: ViewMode {
        get { ViewMode(rawValue: viewModeRaw) ?? .list }
    }
    @State private var lastWeekReflection: WeeklyReflection?
    @State private var shouldOfferReflection: Bool = false
    @State private var isGeneratingReflection: Bool = false
    @State private var presentedReflection: WeeklyReflection?
    @State private var reflectionReadyTrigger: Int = 0

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
                switch viewMode {
                case .list:
                    JournalEntriesList(
                        journal: journal,
                        promptCard: { promptCardView },
                        onDelete: delete,
                        onRefresh: { await refreshPrompt() }
                    )
                case .calendar:
                    ScrollView {
                        VStack(spacing: Spacing.m) {
                            promptCardView
                                .padding(.horizontal, Spacing.m)
                            CalendarMonthView(
                                journal: journal,
                                accent: accent,
                                onSelectDate: { _ in }
                            )
                            Spacer(minLength: 80)
                        }
                        .padding(.top, Spacing.s)
                    }
                    .navigationDestination(for: Entry.self) { entry in
                        EntryDetailView(entry: entry)
                    }
                }
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
        .navigationTitle(currentJournal?.name ?? "Inkus")
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
                    viewModeRaw = (viewMode == .list ? ViewMode.calendar : ViewMode.list).rawValue
                } label: {
                    Image(systemName: viewMode == .list ? "calendar" : "list.bullet")
                }
                .accessibilityLabel(viewMode == .list ? "Switch to calendar view" : "Switch to list view")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Search")
                .keyboardShortcut("f", modifiers: .command)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
                .keyboardShortcut(",", modifiers: .command)
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
        .sensoryFeedback(.success, trigger: reflectionReadyTrigger)
        .onReceive(NotificationCenter.default.publisher(for: .inklingNewEntryRequested)) { _ in
            startNewEntry()
        }
        .onReceive(NotificationCenter.default.publisher(for: .inklingShowWeeklyReflectionRequested)) { _ in
            handleReflectionTap()
        }
        .onReceive(NotificationCenter.default.publisher(for: .inklingShowSearchRequested)) { _ in
            showingSearch = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .inklingShowSettingsRequested)) { _ in
            showingSettings = true
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
                reflectionReadyTrigger += 1
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
        .keyboardShortcut("n", modifiers: .command)
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
        // Cascade-delete on the @Relationship from Entry → Attachment removes
        // the attachments automatically; no on-disk cleanup required now that
        // attachments live in SwiftData.
        modelContext.delete(entry)
        try? modelContext.save()
    }

    private func loadPromptIfNeeded() async {
        guard todaysPrompt == nil else { return }
        let service = DailyPromptService(context: modelContext)
        todaysPrompt = await service.todaysPrompt()
        publishPromptToWidget()
    }

    private func refreshPrompt() async {
        let service = DailyPromptService(context: modelContext)
        todaysPrompt = await service.regenerate()
        publishPromptToWidget()
    }

    /// Mirror today's prompt into the App Group cache so the widget can read it
    /// without touching SwiftData or running AI inference itself.
    private func publishPromptToWidget() {
        guard let prompt = todaysPrompt else { return }
        let accentHex = currentJournal?.accentColorHex ?? "#4F46E5"
        let snapshot = SharedPromptCache.Snapshot(
            date: prompt.date,
            promptText: prompt.promptText,
            followUps: prompt.followUps,
            sourceIsAI: prompt.sourceIsAI,
            accentHex: accentHex
        )
        SharedPromptCache.write(snapshot)
        WidgetReloadCoordinator.reloadPromptWidgets()
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
                        HStack(alignment: .firstTextBaseline) {
                            Text(dayHeader(for: group.date))
                                .font(.system(.title3, design: .serif).weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(group.date.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(group.entries.count) \(group.entries.count == 1 ? "entry" : "entries")")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }
                        .padding(.vertical, Spacing.xs)
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
    .modelContainer(InkusPersistence.makeContainer(inMemory: true))
}
