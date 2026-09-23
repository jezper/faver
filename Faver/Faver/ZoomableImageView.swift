import Photos
import SwiftUI

/// Full-screen image viewer. Starts fitted to the screen; pinch zooms up to 5×.
/// UIScrollView owns zoom/pan so its gesture takes priority over TabView paging
/// while zoomed in, then releases at minimum scale.
struct ZoomableImageView: View {
    let asset: PHAsset

    @State private var image: UIImage? = nil
    @State private var onlyInCloud = false

    var body: some View {
        Group {
            if let image {
                _ZoomScrollView(image: image)
                    .ignoresSafeArea()
            } else if onlyInCloud {
                cloudOnlyNotice
            } else {
                Color.black
                    .overlay { ProgressView().tint(.white) }
            }
        }
        // Two passes. The first takes whatever is already on the device and puts it on
        // screen straight away; the second fetches the full original, which may need
        // the network, and swaps it in when it arrives.
        //
        // This screen used to make a single maximum-size, high-quality request with
        // the network switched on, no low-resolution pass and no timeout. On a train
        // with bad signal the core loop of the app was a spinner on black — which the
        // project rules forbid in as many words: never stall waiting for iCloud.
        .task(id: asset.localIdentifier) {
            image = nil
            onlyInCloud = false

            // A fixed target rather than the screen's. UIScreen.main is deprecated, and
            // this pass exists to put something up instantly; the full-size original
            // replaces it a moment later anyway. 1600 is past a phone's long edge at 2x
            // and decodes quickly.
            let local = await PhotoImage.request(
                for: asset,
                targetSize: CGSize(width: 1600, height: 1600),
                allowsNetwork: false
            )
            if Task.isCancelled { return }

            if let local {
                image = local
            } else {
                // Nothing cached at all, so this photo lives only in iCloud. Say so
                // rather than spinning at the user indefinitely.
                onlyInCloud = true
            }

            let full = await PhotoImage.request(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                allowsNetwork: true
            )
            if Task.isCancelled { return }
            if let full {
                image = full
                onlyInCloud = false
            }
        }
    }

    private var cloudOnlyNotice: some View {
        ZStack {
            Color.black
            VStack(spacing: 12) {
                Image(systemName: "icloud.and.arrow.down")
                    .font(.largeTitle)
                    .foregroundStyle(.white.opacity(0.6))
                Text("Still in iCloud")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.8))
                Text("Fetching it now. Swipe on if you'd rather not wait.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
            .padding(36)
        }
    }

}

// MARK: - Shared image request

/// One place for "give me this asset as a UIImage". Both the still viewer and the video
/// poster need it, and getting cancellation right matters enough not to write twice.
nonisolated enum PhotoImage {
    /// Cancelling the request matters as much as making it: swiping through a set
    /// leaves a trail of full-size decodes running for photos already off screen.
    static func request(
        for asset: PHAsset,
        targetSize: CGSize,
        allowsNetwork: Bool,
        resize: PHImageRequestOptionsResizeMode = .fast
    ) async -> UIImage? {
        let manager = PHImageManager.default()
        nonisolated(unsafe) var requestID: PHImageRequestID?

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
                let options = PHImageRequestOptions()
                options.isNetworkAccessAllowed = allowsNetwork
                options.deliveryMode = allowsNetwork ? .highQualityFormat : .fastFormat
                options.resizeMode = resize
                nonisolated(unsafe) var done = false
                requestID = manager.requestImage(
                    for: asset,
                    targetSize: targetSize,
                    contentMode: .aspectFit,
                    options: options
                ) { image, info in
                    let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
                    if isDegraded { return }
                    guard !done else { return }
                    done = true
                    continuation.resume(returning: image)
                }
            }
        } onCancel: {
            if let requestID { manager.cancelImageRequest(requestID) }
        }
    }
}

// MARK: - UIScrollView subclass

/// Fires `onBoundsChange` whenever the scroll view's size actually changes so
/// the fit-to-screen setup runs at the right moment for every page, not just
/// the first one visible when the ReviewView opens.
private class ZoomScroll: UIScrollView {
    var onBoundsChange: (() -> Void)?
    private var lastSize = CGSize.zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastSize else { return }
        lastSize = bounds.size
        onBoundsChange?()
    }
}

// MARK: - UIScrollView wrapper

private struct _ZoomScrollView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> ZoomScroll {
        let scroll = ZoomScroll()
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.backgroundColor = .black
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.delegate = context.coordinator

        let iv = UIImageView(image: image)
        iv.contentMode = .scaleAspectFit
        scroll.addSubview(iv)

        let coord = context.coordinator
        coord.imageView = iv

        // Re-run setup whenever the scroll view is given a new size (first layout,
        // orientation change, or becoming visible after TabView pre-load).
        scroll.onBoundsChange = { [weak coord, weak scroll] in
            guard let coord, let scroll else { return }
            coord.setup(scroll: scroll)
        }

        let tap = UITapGestureRecognizer(
            target: coord,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        tap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(tap)

        return scroll
    }

    func updateUIView(_ scroll: ZoomScroll, context: Context) {
        let coord = context.coordinator
        let imageChanged = coord.lastImage !== image
        coord.imageView?.image = image
        coord.lastImage = image
        // When image changes, attempt setup immediately (works if already laid out).
        // onBoundsChange will cover the case where bounds aren't ready yet.
        if imageChanged { coord.setup(scroll: scroll) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: Coordinator

    class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        weak var lastImage: UIImage?

        func setup(scroll: UIScrollView) {
            guard let iv = imageView, let img = iv.image else { return }
            let scrollSize = scroll.bounds.size
            guard scrollSize.width > 0, scrollSize.height > 0 else { return }
            let imgSize = img.size
            guard imgSize.width > 0, imgSize.height > 0 else { return }

            // Size the image view to the image's natural pixel dimensions and
            // reset any previous transform so scale math starts from a clean state.
            iv.transform = .identity
            iv.frame = CGRect(origin: .zero, size: imgSize)

            let fitScale = min(scrollSize.width  / imgSize.width,
                               scrollSize.height / imgSize.height)
            scroll.minimumZoomScale = fitScale
            scroll.maximumZoomScale = max(fitScale * 5, 1.0)
            scroll.setZoomScale(fitScale, animated: false)
            // At fit scale the image doesn't scroll — disable so TabView owns the swipe.
            scroll.isScrollEnabled = false

            // setZoomScale does not reliably update contentSize programmatically.
            // Without this explicit set, contentSize stays at the full natural pixel
            // dimensions (e.g. 3000×4000). UIScrollView then thinks there is a huge
            // scrollable area in every direction, causing two bugs:
            //   1. The pan gesture intercepts TabView's horizontal swipes (stuck halfway).
            //   2. The image renders at 1:1 scale rather than fitted to the screen.
            let displayedW = imgSize.width  * fitScale
            let displayedH = imgSize.height * fitScale
            scroll.contentSize = CGSize(width: displayedW, height: displayedH)

            center(in: scroll, resetOffset: true)
        }

        /// Centers the image in the scroll view using contentInset (Apple PhotoScroller approach).
        ///
        /// Note: after UIScrollView applies a zoom transform, `iv.frame` already reflects
        /// the scaled dimensions — use `iv.frame.size` directly. Do NOT multiply
        /// `iv.frame.width * zoomScale`; that would square the scale factor.
        func center(in scroll: UIScrollView, resetOffset: Bool) {
            guard let iv = imageView else { return }
            let dispW = iv.frame.size.width
            let dispH = iv.frame.size.height
            let inX = max((scroll.bounds.width  - dispW) / 2, 0)
            let inY = max((scroll.bounds.height - dispH) / 2, 0)
            scroll.contentInset = UIEdgeInsets(top: inY, left: inX, bottom: inY, right: inX)
            if resetOffset {
                scroll.contentOffset = CGPoint(x: -inX, y: -inY)
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let iv = imageView else { return }
            // Keep contentSize in sync with the actual displayed dimensions as the user
            // pinches. At minimum zoom this makes the image exactly fill the scroll view's
            // content area, so the pan gesture does not intercept TabView swipes.
            scrollView.contentSize = iv.frame.size
            let inX = max((scrollView.bounds.width  - iv.frame.width)  / 2, 0)
            let inY = max((scrollView.bounds.height - iv.frame.height) / 2, 0)
            scrollView.contentInset = UIEdgeInsets(top: inY, left: inX, bottom: inY, right: inX)
            // When the image fits within the screen, snap it to center.
            if inX > 0 || inY > 0 {
                scrollView.contentOffset = CGPoint(x: -inX, y: -inY)
            }
            // Only allow panning when actually zoomed in; at fit scale pass touches to TabView.
            scrollView.isScrollEnabled = scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView else { return }
            if scroll.zoomScale > scroll.minimumZoomScale + 0.01 {
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
