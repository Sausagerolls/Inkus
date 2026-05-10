import SwiftUI
import SwiftData

struct ExportView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Journal.sortOrder) private var journals: [Journal]

    @State private var generatedURL: URL?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Text("Export your entries as Markdown (plain text) or PDF. Files are written to a temporary location and shared via the system share sheet — they never leave your device unless you choose to send them.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(journals) { journal in
                Section(journal.name) {
                    Button {
                        export(journal: journal, asPDF: false)
                    } label: {
                        Label("Markdown", systemImage: "doc.text")
                    }
                    .disabled(isWorking)
                    Button {
                        export(journal: journal, asPDF: true)
                    } label: {
                        Label("PDF", systemImage: "doc.richtext")
                    }
                    .disabled(isWorking)
                }
            }

            if let message = errorMessage {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isWorking {
                ProgressView("Preparing…")
                    .padding(Spacing.l)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .sheet(item: Binding(get: {
            generatedURL.map(ShareableURL.init)
        }, set: { newValue in
            generatedURL = newValue?.url
        })) { wrapper in
            ShareSheet(items: [wrapper.url])
        }
    }

    private func export(journal: Journal, asPDF: Bool) {
        isWorking = true
        errorMessage = nil
        Task { @MainActor in
            defer { isWorking = false }
            do {
                let url = asPDF
                    ? try ExportService.exportJournalPDF(journal)
                    : try ExportService.exportJournalMarkdown(journal)
                generatedURL = url
            } catch {
                errorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }
}

private struct ShareableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
