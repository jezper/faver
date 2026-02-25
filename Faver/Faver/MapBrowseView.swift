import CoreLocation
import MapKit
import Photos
import SwiftUI

// MARK: - MapSuperCluster

/// A screen-space cluster of one or more PhotoClusters, used for map display.
/// At high zoom → one per PhotoCluster. At low zoom → many PhotoClusters merged.
private struct MapSuperCluster: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let photoCount: Int
    let clusters: [PhotoCluster]

    var isSingle: Bool { clusters.count == 1 }
}

// MARK: - MapBrowseView

/// Browse clusters on a world map. Tap a pin to see the cluster and start reviewing.
struct MapBrowseView: View {
    @ObservedObject var photoLibrary: PhotoLibraryService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCluster: PhotoCluster?
    @State private var reviewingCluster: PhotoCluster?
    @State private var cameraPosition: MapCameraPosition = .automatic
    /// Span of the last settled camera position — drives the clustering grid size.
    @State private var currentSpan = MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 360)

    var locatedClusters: [PhotoCluster] {
        photoLibrary.filteredClusters.filter { $0.firstLocationAsset?.location != nil }
    }

    /// Computed synchronously from locatedClusters + currentSpan.
    /// Divides the world into a 5×5 grid (~25 pins max) scaled to the visible span.
    /// Fewer, larger pins leave more map surface exposed for pinch-zoom gestures.
    private var displayClusters: [MapSuperCluster] {
        let gridLat = max(currentSpan.latitudeDelta / 5, 0.001)
        let gridLon = max(currentSpan.longitudeDelta / 5, 0.001)

        var cells: [String: [PhotoCluster]] = [:]
        for cluster in locatedClusters {
            guard let coord = cluster.firstLocationAsset?.location?.coordinate else { continue }
            let row = Int(floor(coord.latitude / gridLat))
            let col = Int(floor(coord.longitude / gridLon))
            cells["\(row),\(col)", default: []].append(cluster)
        }

        return cells.compactMap { key, group in
            let lats = group.compactMap { $0.firstLocationAsset?.location?.coordinate.latitude }
            let lons = group.compactMap { $0.firstLocationAsset?.location?.coordinate.longitude }
            guard !lats.isEmpty else { return nil }
            let avgLat = lats.reduce(0, +) / Double(lats.count)
            let avgLon = lons.reduce(0, +) / Double(lons.count)
            return MapSuperCluster(
                id: key,
                coordinate: CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon),
                photoCount: group.reduce(0) { $0 + $1.count },
                clusters: group
            )
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if locatedClusters.isEmpty && !photoLibrary.isLoading {
                    VStack(spacing: 16) {
                        Image(systemName: "map.slash")
                            .font(.system(size: 56))
                            .foregroundStyle(.secondary)
                        Text("No location data")
                            .font(.title2)
                        Text("These photos don't have GPS coordinates. Location browse works best with photos taken on a smartphone after around 2012.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }
                    .padding()
                } else {
                    Map(position: $cameraPosition) {
                        ForEach(displayClusters) { superCluster in
                            Annotation("", coordinate: superCluster.coordinate) {
                                superClusterPin(superCluster)
                            }
                        }
                    }
                    .onMapCameraChange(frequency: .onEnd) { context in
                        currentSpan = context.region.span
                    }
                }
            }
            .navigationTitle("Browse by location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // Cluster detail sheet — shown when a single pin is tapped
        .sheet(item: $selectedCluster) { cluster in
            VStack(spacing: 0) {
                Capsule()
                    .fill(.secondary.opacity(0.4))
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                MapClusterPreview(cluster: cluster)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                Button(action: {
                    selectedCluster = nil
                    reviewingCluster = cluster
                }) {
                    Text("Start reviewing")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.hidden)
        }
        .fullScreenCover(item: $reviewingCluster, onDismiss: {
            photoLibrary.loadAssets()
        }) { cluster in
            ReviewView(photoLibrary: photoLibrary, assets: cluster.assetsToReview)
        }
    }

    // MARK: - Pin views

    @ViewBuilder
    private func superClusterPin(_ superCluster: MapSuperCluster) -> some View {
        if superCluster.isSingle {
            // Leaf cluster — show sheet on tap.
            // Using .onTapGesture instead of Button so MapKit's pinch/pan
            // gesture recognizers aren't blocked by a UIButton touch handler.
            ZStack {
                Circle().fill(.thinMaterial)
                HStack(spacing: 3) {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 9))
                    Text(compactCount(superCluster.photoCount))
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.primary)
            }
            .frame(width: 44, height: 44)
            .glassEffect(in: Circle())
            .contentShape(Circle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(superCluster.photoCount) photos. Double tap to preview.")
            .accessibilityAddTraits(.isButton)
            .onTapGesture { selectedCluster = superCluster.clusters.first }
        } else {
            // Aggregated cluster — zoom in on tap.
            // Sets count is the primary label; photo count is compact context.
            ZStack {
                Circle().fill(.thinMaterial)
                VStack(spacing: 2) {
                    Text("\(superCluster.clusters.count)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                    HStack(spacing: 2) {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 8))
                        Text(compactCount(superCluster.photoCount))
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .frame(width: 56, height: 56)
            .glassEffect(in: Circle())
            .contentShape(Circle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(superCluster.clusters.count) sets, \(superCluster.photoCount) photos. Double tap to zoom in.")
            .accessibilityAddTraits(.isButton)
            .onTapGesture { zoomInto(superCluster) }
        }
    }

    /// Compact number: 999 → "999", 1200 → "1.2k", 10000 → "10k"
    private func compactCount(_ n: Int) -> String {
        guard n >= 1000 else { return "\(n)" }
        let k = Double(n) / 1000
        return k < 10 ? String(format: "%.1fk", k) : "\(Int(k))k"
    }

    private func zoomInto(_ superCluster: MapSuperCluster) {
        withAnimation {
            cameraPosition = .region(MKCoordinateRegion(
                center: superCluster.coordinate,
                span: MKCoordinateSpan(
                    latitudeDelta: currentSpan.latitudeDelta / 4,
                    longitudeDelta: currentSpan.longitudeDelta / 4
                )
            ))
        }
    }
}

// MARK: - MapClusterPreview

/// 2×2 photo grid used inside the map bottom sheet.
private struct MapClusterPreview: View {
    let cluster: PhotoCluster

    @State private var thumbnails: [UIImage] = []
    @State private var locationName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { geo in
                let cellSize = (geo.size.width - 4) / 2
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        thumbnailCell(index: 0, size: cellSize)
                        thumbnailCell(index: 1, size: cellSize)
                    }
                    HStack(spacing: 4) {
                        thumbnailCell(index: 2, size: cellSize)
                        thumbnailCell(index: 3, size: cellSize)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(cluster.title)
                    .font(.headline)
                HStack(spacing: 4) {
                    Text(cluster.dateLabel)
                    if let place = locationName {
                        Text("·")
                        Text(place)
                    }
                    Text("·")
                    Text("\(cluster.count) photos")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(.horizontal, 4)
        }
        .task(id: cluster.id) {
            await loadThumbnails()
            locationName = await GeocodingCache.shared.lookup(cluster.firstLocationAsset?.location)
        }
    }

    @ViewBuilder
    private func thumbnailCell(index: Int, size: CGFloat) -> some View {
        Group {
            if index < thumbnails.count {
                Image(uiImage: thumbnails[index])
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(.gray.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
        .clipped()
    }

    private func loadThumbnails() async {
        let assets = Array(cluster.assetsToReview.prefix(4))
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
