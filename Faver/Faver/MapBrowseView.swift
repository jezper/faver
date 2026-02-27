import CoreLocation
import MapKit
import Photos
import SwiftUI

// MARK: - Map super-cluster pin

/// Either a single PhotoCluster (leaf) or several clusters grouped into one
/// aggregate pin because they're close together at the current zoom level.
struct MapSuperCluster: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let clusters: [PhotoCluster]

    var isLeaf: Bool { clusters.count == 1 }
    /// Total unreviewed photos represented by this pin.
    var photoCount: Int { clusters.reduce(0) { $0 + $1.count } }
}

// MARK: - Map view

struct MapBrowseView: View {
    let library: LibraryService
    let onSelect: (PhotoCluster) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var position: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 20, longitude: 10),
        span: MKCoordinateSpan(latitudeDelta: 120, longitudeDelta: 180)
    ))
    @State private var currentRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 20, longitude: 10),
        span: MKCoordinateSpan(latitudeDelta: 120, longitudeDelta: 180)
    )
    @State private var selectedPin: MapSuperCluster? = nil

    private var geoClusters: [PhotoCluster] {
        library.filtered.filter { $0.firstLocationAsset?.location != nil }
    }

    private var displayPins: [MapSuperCluster] {
        gridCluster(geoClusters, region: currentRegion)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $position) {
                    ForEach(displayPins) { pin in
                        Annotation("", coordinate: pin.coordinate, anchor: .center) {
                            PinView(pin: pin) {
                                if pin.isLeaf {
                                    selectedPin = pin
                                } else {
                                    zoomIn(to: pin)
                                }
                            }
                        }
                    }
                }
                .onMapCameraChange(frequency: .onEnd) { ctx in
                    currentRegion = ctx.region
                }
                .mapStyle(.hybrid(elevation: .realistic))
                .ignoresSafeArea(edges: .bottom)

                if geoClusters.isEmpty {
                    emptyState
                }
            }
            .navigationTitle("Places")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $selectedPin) { pin in
            if let cluster = pin.clusters.first {
                MapClusterSheet(cluster: cluster) {
                    selectedPin = nil
                    dismiss()
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        onSelect(cluster)
                    }
                }
            }
        }
        .onAppear {
            if let region = boundingRegion(for: geoClusters) {
                currentRegion = region
                position = .region(region)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "map")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.3))
            Text("No location data")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            Text("Your unreviewed moments don't\nhave location information.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .padding(36)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Zoom

    private func zoomIn(to pin: MapSuperCluster) {
        withAnimation(.easeInOut(duration: 0.4)) {
            let newSpan = MKCoordinateSpan(
                latitudeDelta: max(currentRegion.span.latitudeDelta / 4, 0.005),
                longitudeDelta: max(currentRegion.span.longitudeDelta / 4, 0.005)
            )
            position = .region(MKCoordinateRegion(center: pin.coordinate, span: newSpan))
        }
    }
}

// MARK: - Grid clustering

/// Divides the visible map region into an 8×8 grid and groups clusters by cell.
/// Clusters outside the current region are skipped. Each occupied cell becomes
/// either a leaf pin (one cluster) or an aggregate pin (several clusters).
private func gridCluster(_ clusters: [PhotoCluster], region: MKCoordinateRegion) -> [MapSuperCluster] {
    let gridSize = 8
    let latMin = region.center.latitude  - region.span.latitudeDelta  / 2
    let lonMin = region.center.longitude - region.span.longitudeDelta / 2
    let latMax = latMin + region.span.latitudeDelta
    let lonMax = lonMin + region.span.longitudeDelta
    let latStep = region.span.latitudeDelta  / Double(gridSize)
    let lonStep = region.span.longitudeDelta / Double(gridSize)

    var cells: [String: [PhotoCluster]] = [:]

    for cluster in clusters {
        guard let loc = cluster.firstLocationAsset?.location else { continue }
        let lat = loc.coordinate.latitude
        let lon = loc.coordinate.longitude
        guard lat >= latMin, lat <= latMax, lon >= lonMin, lon <= lonMax else { continue }
        let col = max(0, min(gridSize - 1, Int((lat - latMin) / latStep)))
        let row = max(0, min(gridSize - 1, Int((lon - lonMin) / lonStep)))
        cells["\(col)-\(row)", default: []].append(cluster)
    }

    return cells.compactMap { key, pinClusters in
        let lats = pinClusters.compactMap { $0.firstLocationAsset?.location?.coordinate.latitude }
        let lons = pinClusters.compactMap { $0.firstLocationAsset?.location?.coordinate.longitude }
        guard !lats.isEmpty else { return nil }
        return MapSuperCluster(
            id: key,
            coordinate: CLLocationCoordinate2D(
                latitude:  lats.reduce(0, +) / Double(lats.count),
                longitude: lons.reduce(0, +) / Double(lons.count)
            ),
            clusters: pinClusters
        )
    }
}

// MARK: - Bounding region

private func boundingRegion(for clusters: [PhotoCluster]) -> MKCoordinateRegion? {
    let lats = clusters.compactMap { $0.firstLocationAsset?.location?.coordinate.latitude }
    let lons = clusters.compactMap { $0.firstLocationAsset?.location?.coordinate.longitude }
    guard !lats.isEmpty else { return nil }
    let minLat = lats.min()!, maxLat = lats.max()!
    let minLon = lons.min()!, maxLon = lons.max()!
    return MKCoordinateRegion(
        center: CLLocationCoordinate2D(
            latitude:  (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        ),
        span: MKCoordinateSpan(
            latitudeDelta:  max((maxLat - minLat) * 1.4, 0.5),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.5)
        )
    )
}

// MARK: - Pin view

private struct PinView: View {
    let pin: MapSuperCluster
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            if pin.isLeaf {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.accent)
                    .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2)
            } else {
                ZStack {
                    Circle()
                        .fill(Color.accent)
                        .frame(width: 38, height: 38)
                    Text("\(pin.photoCount)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black)
                }
                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Cluster detail sheet

private struct MapClusterSheet: View {
    let cluster: PhotoCluster
    let onReview: () -> Void

    @State private var thumbnail: UIImage? = nil
    @State private var locationName: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color.surface)
                    if let img = thumbnail {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 4) {
                    Text(cluster.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    HStack(spacing: 4) {
                        Text(cluster.dateLabel)
                        if let place = locationName {
                            Text("· \(place)")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
                    Text("\(cluster.count) photo\(cluster.count == 1 ? "" : "s") to review")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.35))
                }
                Spacer()
            }

            Button(action: onReview) {
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill")
                    Text("Review this moment")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.accent, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(PressScaleStyle())
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .background(Color.bg)
        .presentationDetents([.height(210)])
        .presentationDragIndicator(.visible)
        .task {
            thumbnail = await loadThumbnail()
            locationName = await GeocodingCache.shared.lookup(cluster.firstLocationAsset?.location)
        }
    }

    private func loadThumbnail() async -> UIImage? {
        guard let asset = cluster.assetsToReview.first else { return nil }
        return await withCheckedContinuation { continuation in
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .fastFormat
            opts.resizeMode = .fast
            opts.isNetworkAccessAllowed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 144, height: 144),
                contentMode: .aspectFill,
                options: opts
            ) { img, _ in continuation.resume(returning: img) }
        }
    }
}
