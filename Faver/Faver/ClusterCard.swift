import Photos
import SwiftUI

/// A visual card for one cluster — photo collage with title/date/location overlaid
/// on a gradient, matching the editorial style of the year-level cards.
struct ClusterCard: View {
    let cluster: PhotoCluster

    @State private var thumbnails: [UIImage] = []
    @State private var locationName: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            // Photo collage
            collage

            // Liquid Glass info strip
            VStack(alignment: .leading, spacing: 3) {
                Text(cluster.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(cluster.dateLabel)
                    if let place = locationName {
                        Text("·")
                        Text(place)
                    }
                    Text("·")
                    Text("\(cluster.count) photos")
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .glassEffect(in: RoundedRectangle(cornerRadius: 6))
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 7)
        .task(id: cluster.id) {
            await loadThumbnails()
            locationName = await GeocodingCache.shared.lookup(cluster.firstLocationAsset?.location)
        }
    }

    // MARK: - Collage layout

    @ViewBuilder
    private var collage: some View {
        GeometryReader { geo in
            if thumbnails.isEmpty {
                Rectangle().fill(.secondary.opacity(0.12))
            } else if thumbnails.count == 1 {
                photoCell(thumbnails[0])
            } else if thumbnails.count == 2 {
                HStack(spacing: 2) {
                    photoCell(thumbnails[0])
                    photoCell(thumbnails[1])
                }
            } else {
                // 3 photos: tall on the left, two stacked on the right
                HStack(spacing: 2) {
                    photoCell(thumbnails[0])
                        .frame(width: geo.size.width * 0.60)
                    VStack(spacing: 2) {
                        photoCell(thumbnails[1])
                        photoCell(thumbnails[2])
                    }
                    .frame(width: geo.size.width * 0.40 - 2)
                }
            }
        }
    }

    @ViewBuilder
    private func photoCell(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }

    // MARK: - Thumbnail loading

    private func loadThumbnails() async {
        let assets = Array(cluster.assetsToReview.prefix(3))
        var indexed: [(Int, UIImage)] = []
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for (i, asset) in assets.enumerated() {
                group.addTask { (i, await loadThumbnail(for: asset)) }
            }
            for await (i, img) in group {
                if let img { indexed.append((i, img)) }
            }
        }
        thumbnails = indexed.sorted { $0.0 < $1.0 }.map { $0.1 }
    }

    private func loadThumbnail(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 200, height: 200),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
