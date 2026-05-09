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
            if !entry.photoFilenames.isEmpty {
                attachmentStrip
                    .padding(Spacing.m)
            }
        }
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                ForEach(entry.photoFilenames, id: \.self) { filename in
                    if let img = AttachmentStore.loadPhoto(filename: filename, for: entry.id) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    removePhoto(filename: filename)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                        .font(.title3)
                                }
                                .offset(x: 6, y: -6)
                            }
                    }
                }
            }
        }
        .padding(.vertical, Spacing.xs)
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
    }

    private func persist() {
        guard entry.body != draftBody else { return }
        entry.body = draftBody
        entry.updatedAt = .now
        try? modelContext.save()
    }

    private func done() {
        saveTask?.cancel()
        moodSuggestionTask?.cancel()
        persist()
        if isNewDraft && draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && entry.photoFilenames.isEmpty {
            let id = entry.id
            modelContext.delete(entry)
            try? modelContext.save()
            AttachmentStore.deleteAllAttachments(for: id)
        }
        dismiss()
    }

    private func cancel() {
        saveTask?.cancel()
        moodSuggestionTask?.cancel()
        if isNewDraft && draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && entry.photoFilenames.isEmpty {
            let id = entry.id
            modelContext.delete(entry)
            try? modelContext.save()
            AttachmentStore.deleteAllAttachments(for: id)
        }
        dismiss()
    }

    private func importPickedPhotos(_ items: [PhotosPickerItem]) {
        isImporting = true
        let entryID = entry.id
        Task { @MainActor in
            defer { isImporting = false; pickerItems = [] }
            var savedFilenames: [String] = []
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                if let filename = try? AttachmentStore.savePhoto(data, for: entryID) {
                    savedFilenames.append(filename)
                }
            }
            entry.photoFilenames.append(contentsOf: savedFilenames)
            entry.updatedAt = .now
            try? modelContext.save()
        }
    }

    private func removePhoto(filename: String) {
        AttachmentStore.deletePhoto(filename: filename, for: entry.id)
        entry.photoFilenames.removeAll { $0 == filename }
        entry.updatedAt = .now
        try? modelContext.save()
    }
}
