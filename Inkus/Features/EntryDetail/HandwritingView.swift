import SwiftUI
import PencilKit
import Vision
import UIKit

/// PencilKit canvas + Vision OCR. The user writes by hand, taps "Insert as
/// text", and the recognised text is appended to the editor's body via the
/// `onInsert` callback. All processing is local — `VNRecognizeTextRequest`
/// runs on-device.
struct HandwritingView: View {
    @Environment(\.dismiss) private var dismiss

    let onInsert: (String) -> Void

    @State private var drawing: PKDrawing = PKDrawing()
    @State private var isRecognising = false
    @State private var recognised: String = ""

    private let canvasSize = CGSize(width: 1400, height: 900)
    private let paper = UIColor(red: 0xFA/255.0, green: 0xF6/255.0, blue: 0xEE/255.0, alpha: 1.0)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Recognised-so-far preview strip.
                if !recognised.isEmpty {
                    ScrollView {
                        Text(recognised)
                            .font(.system(.callout, design: .serif))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Spacing.m)
                    }
                    .frame(maxHeight: 120)
                    .background(Color.inkSecondary)
                }

                ZStack {
                    Color(uiColor: paper).ignoresSafeArea()
                    PencilCanvas(
                        drawing: $drawing,
                        showsToolPicker: true,
                        allowsFingerDrawing: true,
                        canvasBackgroundColor: paper
                    )
                }
            }
            .navigationTitle("Handwriting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await recognise() }
                    } label: {
                        if isRecognising {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Recognise")
                        }
                    }
                    .disabled(isRecognising || drawing.bounds.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Insert", action: insert)
                        .fontWeight(.semibold)
                        .disabled(recognised.isEmpty)
                }
            }
        }
    }

    private func insert() {
        onInsert(recognised)
        dismiss()
    }

    private func recognise() async {
        isRecognising = true
        defer { isRecognising = false }

        let png = PencilDrawingIO.renderPNG(
            drawing: drawing,
            size: canvasSize,
            backgroundColor: paper
        )
        guard let png, let cgImage = UIImage(data: png)?.cgImage else { return }

        let result: String = await withCheckedContinuation { cont in
            let request = VNRecognizeTextRequest { req, _ in
                let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                cont.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "en-GB"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                cont.resume(returning: "")
            }
        }
        recognised = result
    }
}
