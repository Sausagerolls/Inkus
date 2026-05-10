import SwiftUI
import UIKit

/// Full-screen lightbox for photos / scans / drawings. Pinch + double-tap
/// to zoom, drag to pan, swipe horizontally to step between attachments
/// in the same entry. Audio attachments are skipped here — they're already
/// playable inline via AudioAttachmentPlayer.
struct AttachmentViewerView: View {
    @Environment(\.dismiss) private var dismiss

    let attachments: [Attachment]
    @State var selectedIndex: Int

    @State private var sharedURL: URL?

    private var visualAttachments: [Attachment] {
        attachments.filter { $0.kind != .audio }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedIndex) {
                ForEach(Array(visualAttachments.enumerated()), id: \.element.id) { index, attachment in
                    if let img = AttachmentStore.image(from: attachment) {
                        ZoomableImage(image: img)
                            .tag(index)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: visualAttachments.count > 1 ? .always : .never))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .ignoresSafeArea(edges: .horizontal)

            VStack {
                topBar
                Spacer()
                bottomCaption
            }
        }
        .statusBarHidden(true)
        .sheet(item: Binding(
            get: { sharedURL.map(SharePayload.init) },
            set: { sharedURL = $0?.url }
        )) { wrapper in
            ShareSheet(items: [wrapper.url])
        }
    }

    // MARK: Subviews

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.black.opacity(0.45)))
            }
            .accessibilityLabel("Close")

            Spacer()

            Button {
                share(currentAttachment)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.black.opacity(0.45)))
            }
            .accessibilityLabel("Share")
            .disabled(currentAttachment == nil)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.s)
    }

    @ViewBuilder
    private var bottomCaption: some View {
        if let attachment = currentAttachment {
            VStack(spacing: 4) {
                Text(label(for: attachment))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                if visualAttachments.count > 1 {
                    Text("\(selectedIndex + 1) of \(visualAttachments.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(.vertical, Spacing.m)
            .frame(maxWidth: .infinity)
            .background(.black.opacity(0.45))
        }
    }

    // MARK: Helpers

    private var currentAttachment: Attachment? {
        guard visualAttachments.indices.contains(selectedIndex) else { return nil }
        return visualAttachments[selectedIndex]
    }

    private func label(for attachment: Attachment) -> String {
        switch attachment.kind {
        case .photo:   return "Photo"
        case .scan:    return "Scan"
        case .drawing: return "Drawing"
        case .audio:   return "Audio"
        }
    }

    private func share(_ attachment: Attachment?) {
        guard let attachment, let data = attachment.data else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(attachment.filename)
        try? data.write(to: url, options: .atomic)
        sharedURL = url
    }
}

private struct SharePayload: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

// MARK: ZoomableImage — UIScrollView-backed pinch + double-tap zoom.

struct ZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .black

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        // Double-tap to toggle zoom.
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let location = gesture.location(in: imageView)
                let size = scrollView.bounds.size
                let targetScale = min(scrollView.maximumZoomScale, scrollView.minimumZoomScale * 3)
                let zoomRect = CGRect(
                    x: location.x - (size.width / targetScale) / 2,
                    y: location.y - (size.height / targetScale) / 2,
                    width: size.width / targetScale,
                    height: size.height / targetScale
                )
                scrollView.zoom(to: zoomRect, animated: true)
            }
        }
    }
}
