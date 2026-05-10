#if !targetEnvironment(macCatalyst)
import SwiftUI
import VisionKit
import UIKit

/// Wraps Apple's `VNDocumentCameraViewController`. Each scanned page is
/// returned as a JPEG `Data` blob via `onComplete`. The host view writes
/// each page as a `.scan` Attachment.
///
/// Catalyst doesn't ship VisionKit's camera, so this whole file is gated
/// behind `!targetEnvironment(macCatalyst)`. Mac users use Continuity Camera
/// from the menu bar (Insert from iPhone or iPad → Scan Documents) and the
/// scan syncs back via CloudKit.
struct DocumentScannerView: UIViewControllerRepresentable {
    let onComplete: ([Data]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete, onCancel: onCancel)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onComplete: ([Data]) -> Void
        let onCancel: () -> Void

        init(onComplete: @escaping ([Data]) -> Void, onCancel: @escaping () -> Void) {
            self.onComplete = onComplete
            self.onCancel = onCancel
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            var pages: [Data] = []
            for index in 0..<scan.pageCount {
                let image = scan.imageOfPage(at: index)
                if let jpeg = image.jpegData(compressionQuality: 0.85) {
                    pages.append(jpeg)
                }
            }
            controller.dismiss(animated: true)
            onComplete(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: any Error) {
            controller.dismiss(animated: true)
            onCancel()
        }
    }
}
#endif
