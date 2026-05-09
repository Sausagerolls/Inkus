import SwiftUI
import SwiftData

struct JournalEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// nil = create. non-nil = edit.
    let editing: Journal?
    /// On create, called with the new journal so the caller can mark it selected.
    var onCreated: (Journal) -> Void = { _ in }

    @State private var name: String
    @State private var iconName: String
    @State private var accentHex: String

    init(editing: Journal? = nil, onCreated: @escaping (Journal) -> Void = { _ in }) {
        self.editing = editing
        self.onCreated = onCreated
        _name = State(initialValue: editing?.name ?? "")
        _iconName = State(initialValue: editing?.iconName ?? "book.closed")
        _accentHex = State(initialValue: editing?.accentColorHex ?? "#4F46E5")
    }

    private static let symbolPalette: [String] = [
        "book.closed", "book", "pencil.and.scribble", "text.book.closed",
        "briefcase", "laptopcomputer", "graduationcap", "lightbulb",
        "suitcase", "airplane", "map", "leaf", "tree", "sun.max", "moon.stars",
        "heart", "sparkles", "star", "flame", "drop", "cup.and.saucer",
        "music.note", "camera", "figure.run", "dumbbell", "bicycle",
    ]

    private static let colorPalette: [String] = [
        "#4F46E5", // indigo
        "#7C3AED", // violet
        "#DB2777", // pink
        "#DC2626", // red
        "#C05621", // terracotta
        "#D97706", // amber
        "#65A30D", // lime
        "#2F855A", // forest
        "#0891B2", // cyan
        "#0369A1", // blue
        "#475569", // slate
        "#111827", // ink
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Personal", text: $name)
                        .textInputAutocapitalization(.words)
                }
                Section("Icon") {
                    iconGrid
                }
                Section("Accent") {
                    colorGrid
                }
                Section("Preview") {
                    HStack(spacing: Spacing.m) {
                        Image(systemName: iconName)
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color(hex: accentHex)))
                        Text(name.isEmpty ? "New journal" : name)
                            .font(.body.weight(.medium))
                    }
                    .padding(.vertical, Spacing.xs)
                }
            }
            .navigationTitle(editing == nil ? "New Journal" : "Edit Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var iconGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.s), count: 6),
                  spacing: Spacing.s) {
            ForEach(Self.symbolPalette, id: \.self) { symbol in
                Button {
                    iconName = symbol
                } label: {
                    Image(systemName: symbol)
                        .font(.title3)
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(iconName == symbol ? Color(hex: accentHex).opacity(0.18) : Color.inkSecondary)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(iconName == symbol ? Color(hex: accentHex) : .clear, lineWidth: 2)
                        )
                        .foregroundStyle(iconName == symbol ? Color(hex: accentHex) : .primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private var colorGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.s), count: 6),
                  spacing: Spacing.s) {
            ForEach(Self.colorPalette, id: \.self) { hex in
                Button {
                    accentHex = hex
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle()
                                .stroke(.white, lineWidth: 2)
                                .padding(2)
                                .opacity(accentHex == hex ? 1 : 0)
                        )
                        .overlay(
                            Circle()
                                .stroke(accentHex == hex ? Color.primary : Color.clear, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let existing = editing {
            existing.name = trimmed
            existing.iconName = iconName
            existing.accentColorHex = accentHex
        } else {
            let nextOrder: Int = {
                let descriptor = FetchDescriptor<Journal>(sortBy: [SortDescriptor(\.sortOrder, order: .reverse)])
                let highest = (try? modelContext.fetch(descriptor))?.first?.sortOrder ?? -1
                return highest + 1
            }()
            let new = Journal(
                name: trimmed,
                iconName: iconName,
                accentColorHex: accentHex,
                sortOrder: nextOrder
            )
            modelContext.insert(new)
            try? modelContext.save()
            onCreated(new)
        }
        try? modelContext.save()
        dismiss()
    }
}
