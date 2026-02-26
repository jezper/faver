import Photos
import SwiftUI

/// Full-screen image viewer with pinch-to-zoom (1×–5×) and double-tap to reset.
/// UIScrollView handles zoom so its pan gesture takes priority over TabView paging
/// while the user is zoomed in, then releases control at 1×.
struct ZoomableImageView: View {
    let asset: PHAsset
    @State private var image: UIImage? = nil

    var body: some View {
        Group {
            if let image {
                _ZoomScrollView(image: image)
                    .ignoresSafeArea()
            } else {
                Color.black
                    .overlay { ProgressView().tint(.white) }
            }
        }
        .task(id: asset.localIdentifier) {
            image = await loadImage()
        }
    }

    private func loadImage() async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
                if !isDegraded {
                    continuation.resume(returning: image)
                }
            }
        }
    }
}

// MARK: - UIScrollView wrapper

private struct _ZoomScrollView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.minimumZoomScale = 1.0
        scroll.maximumZoomScale = 5.0
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.backgroundColor = .black
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.delegate = context.coordinator

        let iv = UIImageView(image: image)
        iv.contentMode = .scaleAspectFit
        iv.backgroundColor = .black
        scroll.addSubview(iv)
        context.coordinator.imageView = iv

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        tap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(tap)

        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
        context.coordinator.layoutImageView(in: scroll)
        scroll.setZoomScale(1.0, animated: false)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            layoutImageView(in: scrollView)
        }

        func layoutImageView(in scroll: UIScrollView) {
            guard let iv = imageView else { return }
            if iv.frame.size == .zero { iv.frame = scroll.bounds }
            let offsetX = max((scroll.bounds.width  - iv.frame.width)  / 2, 0)
            let offsetY = max((scroll.bounds.height - iv.frame.height) / 2, 0)
            iv.frame.origin = CGPoint(x: offsetX, y: offsetY)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView else { return }
            if scroll.zoomScale > scroll.minimumZoomScale {
                scroll.setZoomScale(scroll.minimumZoomScale, animated: true)
            } else {
                let pt = gesture.location(in: imageView)
                let w = scroll.bounds.width / 3
                let h = scroll.bounds.height / 3
                scroll.zoom(
                    to: CGRect(x: pt.x - w / 2, y: pt.y - h / 2, width: w, height: h),
                    animated: true
                )
            }
        }
    }
}
