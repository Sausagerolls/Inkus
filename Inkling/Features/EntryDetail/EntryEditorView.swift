import SwiftUI
import SwiftData
import PhotosUI

struct EntryEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var entry: Entry
    /// True when this entry was just inserted by the list view as a draft.
    /// On cancel/dismiss with empty body, we delete the draft so it doesn't pollute the list.
    let isNewDraft: Bool
    /// When set, replaces the default "Start writing…" placeholder.
    var placeholderOverride: String? = nil

    @State private var draftBody: String = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var moodSuggestionTask: Task<Void, Never>?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var pendingMood: MoodSuggestion?
    @State private var dismissedSuggestion = false
    @State private var savedFeedbackTrigger: Int = 0
    @State private var moodAcceptedTrigger: Int = 0
    @State private var showingScanner = false
    @State private var showingDoodle = false
    @State private var showingHandwriting = false
    @State private var showingDictation = false
    @State private var markupTarget: Attachment?
    @State private var drawingToEdit: Attachment?
    @FocusState private var bodyFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            editor
            if let suggestion = pendingMood, !dismissedSuggestion {
                moodPill(suggestion)
            }
            Divider()
            toolbar
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel, action: cancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: done)
                    .fontWeight(.semibold)
            }
        }
        .onAppear {
            draftBody = entry.body
            bodyFocused = entry.body.isEmpty
        }
        .onChange(of: draftBody) { _, _ in
            scheduleSave()
            scheduleMoodSuggestion()
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            importPickedPhotos(items)
        }
        .sensoryFeedback(.success, trigger: savedFeedbackTrigger)
        .sensoryFeedback(.selection, trigger: moodAcceptedTrigger)
        #if !targetEnvironment(macCatalyst)
        .fullScreenCover(isPresented: $showingScanner) {
            DocumentScannerView(
                onComplete: { pages in
                    for page in pages {
                        _ = try? AttachmentStore.saveScan(page, to: entry, in: modelContext)
                    }
                    entry.updatedAt = .now
                    try? modelContext.save()
                    showingScanner = false
                },
                onCancel: { showingScanner = false }
            )
            .ignoresSafeArea()
        }
        #endif
        .sheet(isPresented: $showingDoodle) {
            DoodleView(entry: entry, editing: nil)
        }
        .sheet(isPresented: $showingHandwriting) {
            HandwritingView { recognised in
                appendToBody(recognised)
            }
        }
        .sheet(isPresented: $showingDictation) {
            VoiceDictationView(entry: entry) { recognised in
                appendToBody(recognised)
            }
        }
        .sheet(item: $markupTarget) { attachment in
            ScanMarkupView(attachment: attachment)
        }
        .sheet(item: $drawingToEdit) { attachment in
            DoodleView(entry: entry, editing: attachment)
        }
    }

    // MARK: Subviews

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if draftBody.isEmpty {
                Text(placeholderOverride ?? "Start writing…")
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, Spacing.m + 4)
                    .padding(.top, Spacing.m + 8)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $draftBody)
                .font(.system(.body, design: .serif))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, Spacing.m)
                .padding(.top, Spacing.s)
                .focused($bodyFocused)
        }
        .background(Color.inkBackground)
        .overlay(alignment: .bottom) {
            if !(entry.attachments ?? []).isEmpty {
                attachmentStrip
                    .padding(Spacing.m)
            }
        }
    }

    private var attachmentStrip: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            // Audio attachments get their own row of inline players so the
            // user can play them back without leaving the editor.
            ForEach(audioAttachments) { audio in
                HStack(spacing: Spacing.s) {
                    AudioAttachmentPlayer(attachment: audio)
                    Button {
                        removeAttachment(audio)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.6))
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Visual attachments stay in the horizontal thumbnail strip.
            if !visualAttachments.isEmpty {
                visualThumbStrip
            }
        }
    }

    private var audioAttachments: [Attachment] {
        (entry.attachments ?? []).filter { $0.kind == .audio }
    }

    private var visualAttachments: [Attachment] {
        (entry.attachments ?? []).filter { $0.kind != .audio }
    }

    private var visualThumbStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                ForEach(visualAttachments) { attachment in
                    if let img = AttachmentStore.image(from: attachment) {
                        Button { handleAttachmentTap(attachment) } label: {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        removeAttachment(attachment)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                            .font(.title3)
                                    }
                                    .offset(x: 6, y: -6)
                                }
                                .overlay(alignment: .bottomLeading) {
                                    if attachment.kind != .photo {
                                        Image(systemName: kindGlyph(attachment.kind))
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.white)
                                            .padding(4)
                                            .background(Circle().fill(.black.opacity(0.55)))
                                            .padding(4)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private func kindGlyph(_ kind: AttachmentKind) -> String {
        switch kind {
        case .photo:   return "photo"
        case .audio:   return "waveform"
        case .scan:    return "doc.viewfinder"
        case .drawing: return "pencil.tip"
        }
    }

    private var toolbar: some View {
        HStack(spacing: Spacing.l) {
            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: 5,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Image(systemName: "photo.on.rectangle")
                    .font(.title3)
            }
            .disabled(isImporting)
            .accessibilityLabel("Add photo")

            #if !targetEnvironment(macCatalyst)
            Button {
                showingScanner = true
            } label: {
                Image(systemName: "doc.viewfinder")
                    .font(.title3)
            }
            .accessibilityLabel("Scan document")
            #endif

            Button {
                showingDoodle = true
            } label: {
                Image(systemName: "pencil.tip")
                    .font(.title3)
            }
            .accessibilityLabel("Add doodle")

            Button {
                showingHandwriting = true
            } label: {
                Image(systemName: "hand.draw")
                    .font(.title3)
            }
            .accessibilityLabel("Handwriting input")

            Button {
                showingDictation = true
            } label: {
                Image(systemName: "mic")
                    .font(.title3)
            }
            .accessibilityLabel("Voice dictation")

            Spacer()

            if isImporting {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .background(.regularMaterial)
    }

    private func moodPill(_ suggestion: MoodSuggestion) -> some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(Color.inkAccent)
            Text("Suggested:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(suggestion.emoji) \(suggestion.mood)")
                .font(.callout.weight(.medium))
            Spacer(minLength: 0)
            Button("Accept") {
                acceptMood(suggestion)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(Color.inkAccent)
            Button {
                dismissedSuggestion = true
                pendingMood = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .background(Color.inkSecondary)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.smooth, value: pendingMood?.mood)
    }

    private var navTitle: String {
        entry.createdAt.formatted(.dateTime.weekday(.wide).month().day())
    }

    // MARK: Actions

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            persist()
        }
    }

    private func scheduleMoodSuggestion() {
        guard AIAvailability.isAvailable,
              entry.moodLabel == nil,
              !dismissedSuggestion else { return }
        moodSuggestionTask?.cancel()
        let snapshotBody = draftBody
        guard snapshotBody.trimmingCharacters(in: .whitespacesAndNewlines).count >= 60 else {
            // Too short to be useful — wait until there's more.
            pendingMood = nil
            return
        }
        moodSuggestionTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            guard entry.moodLabel == nil, !dismissedSuggestion else { return }
            do {
                let suggestion = try await MoodSuggester().suggest(for: snapshotBody)
                guard !Task.isCancelled, entry.moodLabel == nil, !dismissedSuggestion else { return }
                pendingMood = suggestion
            } catch {
                // Silent failure — suggestion is non-essential.
            }
        }
    }

    private func acceptMood(_ suggestion: MoodSuggestion) {
        entry.moodLabel = suggestion.mood
        entry.moodEmoji = suggestion.emoji
        entry.moodConfidence = 1.0
        // Merge tag suggestions without duplicates.
        let existing = Set(entry.tags)
        for tag in suggestion.tags where !existing.contains(tag) {
            entry.tags.append(tag)
        }
        entry.updatedAt = .now
        try? modelContext.save()
        pendingMood = nil
        dismissedSuggestion = true
        moodAcceptedTrigger += 1
    }

    private func persist() {
        guard entry.body != draftBody else { return }
        entry.body = draftBody
        entry.updatedAt = .now
        try? modelContext.save()
    }

    private var draftIsEmpty: Bool {
        draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (entry.attachments ?? []).isEmpty
    }

    private func done() {
        saveTask?.cancel()
        moodSuggestionTask?.cancel()
        persist()
        if isNewDraft && draftIsEmpty {
            modelContext.delete(entry)
            try? modelContext.save()
        } else {
            savedFeedbackTrigger += 1
        }
        dismiss()
    }

    private func cancel() {
        saveTask?.cancel()
        moodSuggestionTask?.cancel()
        if isNewDraft && draftIsEmpty {
            modelContext.delete(entry)
            try? modelContext.save()
        }
        dismiss()
    }

    private func importPickedPhotos(_ items: [PhotosPickerItem]) {
        isImporting = true
        Task { @MainActor in
            defer { isImporting = false; pickerItems = [] }
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                _ = try? AttachmentStore.savePhoto(data, to: entry, in: modelContext)
            }
            entry.updatedAt = .now
            try? modelContext.save()
        }
    }

    private func removeAttachment(_ attachment: Attachment) {
        AttachmentStore.delete(attachment, in: modelContext)
        entry.updatedAt = .now
        try? modelContext.save()
    }

    private func handleAttachmentTap(_ attachment: Attachment) {
        switch attachment.kind {
        case .scan:    markupTarget = attachment
        case .drawing: drawingToEdit = attachment
        default:       break
        }
    }

    private func appendToBody(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !draftBody.isEmpty && !draftBody.hasSuffix("\n") {
            draftBody += "\n"
        }
        draftBody += trimmed
    }
}
