import SwiftUI
import SwiftData
import PencilKit
import UIKit

/// Standalone PencilKit canvas saved as a `.drawing` Attachment. Cream paper
/// background, full tool picker. On save, renders a PNG preview alongside the
/// editable PKDrawing data.
struct DoodleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let entry: Entry
    /// Pass an existing drawing attachment to re-edit; nil starts a fresh one.
    let editing: Attachment?

    @State private var drawing: PKDrawing = PKDrawing()

    private let canvasSize = CGSize(width: 1200, height: 1500)
    private let paper = UIColor(red: 0xFA/255.0, green: 0xF6/255.0, blue: 0xEE/255.0, alpha: 1.0)

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: paper).ignoresSafeArea()
                PencilCanvas(
                    drawing: $drawing,
                    showsToolPicker: true,
                    allowsFingerDrawing: true,
                    canvasBackgroundColor: paper
                )
            }
            .navigationTitle(editing == nil ? "Doodle" : "Edit doodle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(drawing.bounds.isEmpty)
                }
            }
        }
        .onAppear {
            if let editing { drawing = PencilDrawingIO.decode(editing.vectorData) }
        }
    }

    private func save() {
        let png = PencilDrawingIO.renderPNG(
            drawing: drawing,
            size: canvasSize,
            backgroundColor: paper
        )
        guard let png else { dismiss(); return }

        if let editing {
            editing.data = png
            editing.vectorData = drawing.dataRepresentation()
            editing.entry?.updatedAt = .now
        } else {
            _ = try? AttachmentStore.saveDrawing(
                rendered: png,
                vectorData: drawing.dataRepresentation(),
                kind: .drawing,
                to: entry,
                in: modelContext
            )
            entry.updatedAt = .now
        }
        try? modelContext.save()
        dismiss()
    }
}
