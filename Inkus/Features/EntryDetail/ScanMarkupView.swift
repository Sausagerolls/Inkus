import SwiftUI
import SwiftData
import PencilKit
import UIKit

/// Opens an existing `.scan` Attachment as a PencilKit-overlay markup canvas.
/// On save, composites the strokes back onto the page image and stores the
/// result, plus the editable `PKDrawing` data, on the same Attachment.
struct ScanMarkupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let attachment: Attachment

    @State private var drawing: PKDrawing = PKDrawing()
    @State private var pageImage: UIImage?

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack {
                    Color.inkBackground.ignoresSafeArea()
                    if let pageImage {
                        Image(uiImage: pageImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                    PencilCanvas(
                        drawing: $drawing,
                        showsToolPicker: true,
                        allowsFingerDrawing: true,
                        canvasBackgroundColor: .clear
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .navigationTitle("Mark up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            pageImage = AttachmentStore.image(from: attachment)
            drawing = PencilDrawingIO.decode(attachment.vectorData)
        }
    }

    private func save() {
        guard let pageImage else { dismiss(); return }
        let renderSize = pageImage.size
        if let png = PencilDrawingIO.renderPNG(
            drawing: drawing,
            size: renderSize,
            background: pageImage
        ) {
            attachment.data = png
            attachment.vectorData = drawing.dataRepresentation()
            attachment.entry?.updatedAt = .now
            try? modelContext.save()
        }
        dismiss()
    }
}
