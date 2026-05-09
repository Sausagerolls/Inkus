import SwiftUI
import SwiftData

/// Popover/menu content listing journals with accent swatches and entry counts,
/// plus a row to create a new one.
struct JournalSwitcherView: View {
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Journal.sortOrder) private var journals: [Journal]

    /// UUID string of the currently-selected journal.
    @Binding var selectedJournalID: String

    /// Triggered when the user taps "New journal".
    var onCreate: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(journals) { journal in
                        Button {
                            selectedJournalID = journal.id.uuidString
                            dismiss()
                        } label: {
                            row(for: journal)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section {
                    Button {
                        dismiss()
                        onCreate()
                    } label: {
                        Label("New journal", systemImage: "plus.circle")
                            .foregroundStyle(Color.inkAccent)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Journals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(for journal: Journal) -> some View {
        let isSelected = (journal.id.uuidString == selectedJournalID)
        return HStack(spacing: Spacing.m) {
            Image(systemName: journal.iconName)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(Color(hex: journal.accentColorHex))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(journal.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text("\(journal.entries.count) \(journal.entries.count == 1 ? "entry" : "entries")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.inkAccent)
            }
        }
        .contentShape(Rectangle())
    }
}
