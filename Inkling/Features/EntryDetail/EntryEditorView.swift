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

    @State private var draftBody: String = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isImporting = false
    @FocusState private var bodyFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            editor
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
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            importPickedPhotos(items)
        }
        .interactiveDismissDisabled(false)
    }

    // MARK: Subviews

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if draftBody.isEmpty {
                Text("Start writing…")
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

    private func persist() {
        guard entry.body != draftBody else { return }
        entry.body = draftBody
        entry.updatedAt = .now
        try? modelContext.save()
    }

    private func done() {
        saveTask?.cancel()
        persist()
        if isNewDraft && draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && entry.photoFilenames.isEmpty {
            // Don't keep an empty draft.
            let id = entry.id
            modelContext.delete(entry)
            try? modelContext.save()
            AttachmentStore.deleteAllAttachments(for: id)
        }
        dismiss()
    }

    private func cancel() {
        saveTask?.cancel()
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
