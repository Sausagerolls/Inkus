import SwiftUI
import PencilKit
import UIKit

/// Thin SwiftUI wrapper around PKCanvasView. Surfaces the system tool picker
/// and writes drawing changes back via the binding.
///
/// Apple Pencil is used when present; finger drawing is enabled too so the
/// app is usable on devices without a Pencil.
struct PencilCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var showsToolPicker: Bool = true
    var allowsFingerDrawing: Bool = true
    var canvasBackgroundColor: UIColor = .systemBackground

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing = drawing
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly
        canvas.backgroundColor = canvasBackgroundColor
        canvas.isOpaque = false
        canvas.alwaysBounceVertical = false

        if showsToolPicker {
            DispatchQueue.main.async {
                guard let window = canvas.window else { return }
                let picker = PKToolPicker.shared(for: window) ?? PKToolPicker()
                picker.setVisible(true, forFirstResponder: canvas)
                picker.addObserver(canvas)
                canvas.becomeFirstResponder()
            }
        }
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.drawing.dataRepresentation() != drawing.dataRepresentation() {
            uiView.drawing = drawing
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilCanvas
        init(_ parent: PencilCanvas) { self.parent = parent }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}

/// Small helpers for rasterising and decoding PKDrawing data.
enum PencilDrawingIO {
    static func decode(_ data: Data?) -> PKDrawing {
        guard let data, let drawing = try? PKDrawing(data: data) else {
            return PKDrawing()
        }
        return drawing
    }

    /// Renders a drawing to a PNG with the given size. Used for previews and
    /// for compositing markup back into a scanned page.
    static func renderPNG(
        drawing: PKDrawing,
        size: CGSize,
        background: UIImage? = nil,
        backgroundColor: UIColor? = nil
    ) -> Data? {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            if let backgroundColor {
                backgroundColor.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
            }
            if let background {
                background.draw(in: CGRect(origin: .zero, size: size))
            }
            let drawingImage = drawing.image(from: CGRect(origin: .zero, size: size), scale: UIScreen.main.scale)
            drawingImage.draw(in: CGRect(origin: .zero, size: size))
        }
        return image.pngData()
    }
}
