import Photos
import SwiftUI

/// Keeps decoded card images around, and fetches them before they are asked for.
///
/// Without this every card fetched its three photos from scratch each time it scrolled
/// into view, and again on the way back from a review session. Full-size decodes, over
/// and over, for images that had already been produced moments earlier.
///
/// Three things happen here:
///
/// **Caching.** A decoded image is kept under the exact size it was produced at. Scroll
/// away and back and it is simply there.
///
/// **Sharing.** Two cards asking for the same photo at the same moment wait on one
/// request rather than starting two.
///
/// **Warming.** The cards for a session are fetched as soon as the moments are known,
/// not when each card happens to appear, and the photos shown last time are fetched at
/// launch while clustering is still running. The library rarely changes between
/// sessions, so the first card is usually already drawn by the time the home screen is.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    /// Photos shown on the home cards last time, so the next launch can start fetching
    /// before it knows what the cards will be. Usually the same answer.
    private let lastCardsKey = "lastHomeCardAssetIDs"

    private let cache = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    /// Separate from PHImageManager.default() on purpose: this one is allowed to hold on
    /// to what it has produced.
    private let manager = PHCachingImageManager()

    private init() {
        // Five cards at the sizes below, plus their throwaway previews, comes to around
        // 65 MB. NSCache hands it all back under memory pressure regardless.
        cache.totalCostLimit = 96 * 1024 * 1024
    }

    // MARK: - Sizes

    /// The first photo of a card fills most of it; the other two are a third of the
    /// height and half the width. Asking for one size for all three either starves the
    /// big one or wastes five times the memory on the small ones.
    /// Sized in pixels for a full-width card on a 3x phone, and cropped to exactly that
    /// by `.exact` — which also stops a panorama from arriving as a 45 MB strip.
    static func size(forIndex index: Int) -> CGSize {
        index == 0
            ? CGSize(width: 1100, height: 1500)
            : CGSize(width: 650, height: 750)
    }

    /// The small square used in lists. 56pt drawn on a 3x screen.
    static let rowSize = CGSize(width: 168, height: 168)

    static let previewSize = CGSize(width: 500, height: 500)

    // MARK: - Reading

    func cached(_ asset: PHAsset, size: CGSize) -> UIImage? {
        cache.object(forKey: key(asset.localIdentifier, size))
    }

    /// Every image of a card, or nothing. A partial set would change which collage layout
    /// the card draws, so it would rearrange itself as the rest arrived.
    func cachedCard(_ cluster: PhotoCluster) -> [UIImage] {
        var images: [UIImage] = []
        for (i, asset) in cluster.assetsToReview.prefix(3).enumerated() {
            guard let image = cached(asset, size: Self.size(forIndex: i)) else { return [] }
            images.append(image)
        }
        return images
    }

    func image(for asset: PHAsset, size: CGSize, allowsNetwork: Bool, exact: Bool) async -> UIImage? {
        let cacheKey = key(asset.localIdentifier, size)
        if let hit = cache.object(forKey: cacheKey) { return hit }

        let id = cacheKey as String
        if let running = inFlight[id] { return await running.value }

        let task = Task { [manager] in
            await Self.request(manager, asset, size, allowsNetwork, exact)
        }
        inFlight[id] = task
        let image = await task.value
        inFlight[id] = nil

        if let image {
            cache.setObject(image, forKey: cacheKey, cost: image.approximateBytes)
        }
        return image
    }

    // MARK: - Warming

    /// Fetches the cards for these moments now, rather than when each one scrolls in.
    func warm(_ clusters: [PhotoCluster]) {
        for cluster in clusters.prefix(5) {
            for (i, asset) in cluster.assetsToReview.prefix(3).enumerated() {
                let size = Self.size(forIndex: i)
                guard cached(asset, size: size) == nil else { continue }
                Task { _ = await image(for: asset, size: size, allowsNetwork: true, exact: true) }
            }
        }
        remember(clusters)
    }

    private func remember(_ clusters: [PhotoCluster]) {
        let ids = clusters.prefix(5).flatMap { $0.assetsToReview.prefix(3).map(\.localIdentifier) }
        UserDefaults.standard.set(Array(ids), forKey: lastCardsKey)
    }

    /// Called at launch, before clustering has finished and therefore before anyone knows
    /// what the cards will be. Last session's answer is nearly always this session's too.
    /// No network: this is a guess, and a guess should not spend anyone's data.
    func warmFromLastLaunch() {
        let ids = UserDefaults.standard.stringArray(forKey: lastCardsKey) ?? []
        guard !ids.isEmpty else { return }

        Task {
            let assets: [String: PHAsset] = await Task.detached(priority: .utility) {
                let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
                var byID: [String: PHAsset] = [:]
                result.enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }
                return byID
            }.value

            for (i, id) in ids.enumerated() {
                guard let asset = assets[id] else { continue }
                // Saved three per card, so position within the card is the index mod 3.
                let size = Self.size(forIndex: i % 3)
                guard cached(asset, size: size) == nil else { continue }
                _ = await image(for: asset, size: size, allowsNetwork: false, exact: true)
            }
        }
    }

    // MARK: - Plumbing

    private func key(_ id: String, _ size: CGSize) -> NSString {
        "\(id)@\(Int(size.width))x\(Int(size.height))" as NSString
    }

    private static func request(
        _ manager: PHCachingImageManager,
        _ asset: PHAsset,
        _ size: CGSize,
        _ allowsNetwork: Bool,
        _ exact: Bool
    ) async -> UIImage? {
        await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = allowsNetwork
            options.deliveryMode = exact ? .highQualityFormat : .opportunistic
            options.resizeMode = exact ? .exact : .fast
            nonisolated(unsafe) var done = false
            nonisolated(unsafe) var fallback: UIImage? = nil
            manager.requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                guard !done else { return }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded { fallback = image; return }
                done = true
                continuation.resume(returning: image ?? fallback)
            }
        }
    }
}

private extension UIImage {
    /// What this image costs the cache, in bytes of pixels.
    var approximateBytes: Int {
        guard let cg = cgImage else { return 1 }
        return cg.bytesPerRow * cg.height
    }
}
