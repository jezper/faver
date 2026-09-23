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
                _ZoomScrollView(image: image, identity: asset.localIdentifier)
                    .ignoresSafeArea()
            } else if onlyInCloud {
                cloudOnlyNotice
            } else {
                Color.black
                    .overlay { ProgressView().tint(.white) }
            }
        }
        // Two passes. The first takes whatever is already on the device and puts it on
        // screen straight away; the second fetches a sharp copy, over the network if it
        // has to, and swaps it in when it arrives.
        //
        // Both ask for the same target, so the second is the same picture at the same
        // proportions — only sharper. When they differed, swapping one for the other
        // changed the geometry underneath the user mid-swipe.
        .task(id: asset.localIdentifier) {
            image = nil
            onlyInCloud = false

            let local = await PhotoImage.request(
                for: asset,
                targetSize: PhotoImage.displaySize,
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

            let sharp = await PhotoImage.request(
                for: asset,
                targetSize: PhotoImage.displaySize,
                allowsNetwork: true,
                resize: .exact
            )
            if Task.isCancelled { return }
            if let sharp {
                image = sharp
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

    /// Big enough to fill any phone screen sharply and to stand a few steps of zoom,
    /// small enough not to hand the main thread a 190 MB decode. PHImageManagerMaximumSize
    /// asks for the whole original, which on a 48 megapixel photo is exactly that.
    static let displaySize = CGSize(width: 3000, height: 3000)

    /// One manager for every full-screen request, so that asking it to prepare the next
    /// few photos actually helps when those photos are reached.
    nonisolated(unsafe) private static let manager = PHCachingImageManager()
    nonisolated(unsafe) private static var prefetching: [PHAsset] = []

    /// Cancelling the request matters as much as making it: swiping through a set
    /// leaves a trail of full-size decodes running for photos already off screen.
    static func request(
        for asset: PHAsset,
        targetSize: CGSize,
        allowsNetwork: Bool,
        resize: PHImageRequestOptionsResizeMode = .fast
    ) async -> UIImage? {
        nonisolated(unsafe) var requestID: PHImageRequestID?

        let image = await withTaskCancellationHandler {
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

        // Unpacked here rather than by the image view on its first draw, which happens on
        // the main thread at exactly the moment the photo is swapped in — the hitch.
        return await image?.byPreparingForDisplay() ?? image
    }

    /// Asks Photos to get these ready. Nothing is held in memory by us; the work and the
    /// iCloud download happen ahead of time so arriving at the photo is instant.
    ///
    /// Stills only. A video's data is far larger, the poster frame is all that shows
    /// until it is asked for, and fetching them in advance would spend a lot of someone's
    /// connection on something they may well swipe straight past.
    static func prefetch(_ assets: [PHAsset]) {
        let stills = assets.filter { $0.mediaType == .image }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact

        if !prefetching.isEmpty {
            manager.stopCachingImages(
                for: prefetching,
                targetSize: displaySize,
                contentMode: .aspectFit,
                options: options
            )
        }
        prefetching = stills
        guard !stills.isEmpty else { return }
        manager.startCachingImages(
            for: stills,
            targetSize: displaySize,
            contentMode: .aspectFit,
            options: options
        )
    }

    static func stopPrefetching() {
        guard !prefetching.isEmpty else { return }
        prefetching = []
        manager.stopCachingImagesForAllAssets()
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
    /// The asset this image belongs to. A new photo starts from scratch; a sharper copy
    /// of the same one must not disturb what the user is doing.
    let identity: String

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
        guard coord.lastImage !== image else { return }
        let isNewPhoto = coord.identity != identity
        coord.identity = identity
        coord.lastImage = image
        coord.imageView?.image = image
        // A new photo resets everything. A sharper copy of the same photo keeps the zoom
        // and the position, because it can land at any moment — including mid-swipe,
        // which is what made paging jump and stutter.
        if isNewPhoto {
            coord.setup(scroll: scroll)
        } else {
            coord.refine(scroll: scroll)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: Coordinator

    class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        weak var lastImage: UIImage?
        var identity: String?

        /// A different photo: start clean, fitted to the screen.
        func setup(scroll: UIScrollView) {
            guard let iv = imageView, let img = iv.image else { return }
            let bounds = scroll.bounds.size
            let size = img.size
            guard bounds.width > 0, bounds.height > 0, size.width > 0, size.height > 0 else { return }

            // First, before any geometry is touched. Between setting a natural-size frame
            // and correcting contentSize the scroll view believes it has thousands of
            // points to pan across, and its pan gesture will happily take a swipe meant
            // for the pager.
            scroll.isScrollEnabled = false

            iv.transform = .identity
            iv.frame = CGRect(origin: .zero, size: size)
            // Natural size, set before the zoom scale. UIScrollView scales this itself as
            // it zooms; the old code set it afterwards and then kept overwriting it.
            scroll.contentSize = size

            let fit = min(bounds.width / size.width, bounds.height / size.height)
            scroll.minimumZoomScale = fit
            scroll.maximumZoomScale = max(fit * 5, 1)
            scroll.zoomScale = fit

            centre(scroll)
            scroll.contentOffset = CGPoint(x: -scroll.contentInset.left, y: -scroll.contentInset.top)
        }

        /// The same photo at a sharper size. Keeps whatever the user was looking at.
        func refine(scroll: UIScrollView) {
            guard let iv = imageView, let img = iv.image else { return }
            let bounds = scroll.bounds.size
            let size = img.size
            guard bounds.width > 0, bounds.height > 0, size.width > 0, size.height > 0 else { return }

            // How far in the user currently is, as a multiple of fit. Pixel dimensions
            // change between the quick copy and the sharp one, so the scale that means
            // "fitted" changes with them; what has to survive is the relationship.
            let oldFit = scroll.minimumZoomScale
            let relative = oldFit > 0 ? scroll.zoomScale / oldFit : 1

            iv.transform = .identity
            iv.frame = CGRect(origin: .zero, size: size)
            scroll.contentSize = size

            let fit = min(bounds.width / size.width, bounds.height / size.height)
            scroll.minimumZoomScale = fit
            scroll.maximumZoomScale = max(fit * 5, 1)
            scroll.zoomScale = fit * relative

            centre(scroll)
            if relative <= 1.01 {
                scroll.contentOffset = CGPoint(x: -scroll.contentInset.left, y: -scroll.contentInset.top)
            }
        }

        /// Centres by padding, never by moving the content. Apple's PhotoScroller approach.
        private func centre(_ scroll: UIScrollView) {
            guard let iv = imageView else { return }
            let x = max((scroll.bounds.width  - iv.frame.width)  / 2, 0)
            let y = max((scroll.bounds.height - iv.frame.height) / 2, 0)
            scroll.contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            // Padding only. This used to rewrite contentSize and force contentOffset on
            // every step of a pinch, which took the anchor away from the user's fingers —
            // the image snapped back instead of following them.
            centre(scrollView)
            // Panning belongs to the photo once zoomed in, and to the pager at fit.
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
