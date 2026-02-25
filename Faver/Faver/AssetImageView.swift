import Photos
import SwiftUI
import UIKit

/// Displays a single photo from the photo library, full screen, with pinch-to-zoom.
/// Uses a UIScrollView under the hood so its zoom gesture naturally takes priority
/// over TabView's page-swipe when the photo is zoomed in — pan within the photo,
/// swipe to next when back at 1×.
struct AssetImageView: View {
    let asset: PHAsset

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                ZoomableScrollView(image: image)
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
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}

// MARK: - ZoomableScrollView

private struct ZoomableScrollView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> LayoutAwareScrollView {
        let scrollView = LayoutAwareScrollView()
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .black
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.bouncesZoom = true
        scrollView.delegate = context.coordinator

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black
        scrollView.addSubview(imageView)

        // Wire up the coordinator so layoutSubviews callbacks reach it
        context.coordinator.imageView = imageView
        scrollView.coordinator = context.coordinator

        // Double-tap: zoom in to tapped point, or reset if already zoomed
        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: LayoutAwareScrollView, context: Context) {
        guard let imageView = context.coordinator.imageView else { return }
        if imageView.image !== image {
            imageView.image = image
            scrollView.setZoomScale(1.0, animated: false)
        }
        // centerImageView is also called from layoutSubviews when bounds are real;
        // call here too in case the image changed after layout already happened.
        context.coordinator.centerImageView(in: scrollView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: Coordinator

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImageView(in: scrollView)
        }

        func centerImageView(in scrollView: UIScrollView) {
            guard let imageView, scrollView.bounds.size != .zero else { return }
            // At 1× the imageView fills the scroll view exactly
            if scrollView.zoomScale == 1.0 {
                imageView.frame = scrollView.bounds
                scrollView.contentSize = scrollView.bounds.size
            }
            // Keep the image centred as the user zooms in/out
            let offsetX = max((scrollView.bounds.width  - imageView.frame.width)  / 2, 0)
            let offsetY = max((scrollView.bounds.height - imageView.frame.height) / 2, 0)
            imageView.center = CGPoint(
                x: imageView.frame.width  / 2 + offsetX,
                y: imageView.frame.height / 2 + offsetY
            )
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let zoomRect = CGRect(
                    x: point.x - scrollView.bounds.width  / 6,
                    y: point.y - scrollView.bounds.height / 6,
                    width:  scrollView.bounds.width  / 3,
                    height: scrollView.bounds.height / 3
                )
                scrollView.zoom(to: zoomRect, animated: true)
            }
        }
    }
}

// MARK: - LayoutAwareScrollView

/// UIScrollView subclass that notifies the coordinator whenever its bounds change
/// (i.e. after UIKit's layout pass). This ensures the imageView is sized correctly
/// the very first time the view appears, when `updateUIView` may be called before
/// the scroll view has non-zero bounds.
private final class LayoutAwareScrollView: UIScrollView {
    weak var coordinator: ZoomableScrollView.Coordinator?

    override func layoutSubviews() {
        super.layoutSubviews()
        coordinator?.centerImageView(in: self)
    }
}
