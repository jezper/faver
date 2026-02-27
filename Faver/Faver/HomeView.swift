import Photos
import SwiftUI

// MARK: - Home screen

struct HomeView: View {
    @StateObject private var library = LibraryService()
    @State private var currentIndex: Int = 0
    @State private var reviewCluster: PhotoCluster? = nil
    @State private var showBrowse = false
    @State private var showSettings = false
    @State private var showMap = false

    @AppStorage("homeCardSort") private var sortRaw: String = "oldest"

    private enum HomeCardSort: String { case oldest, latest }
    private var cardSort: HomeCardSort { HomeCardSort(rawValue: sortRaw) ?? .oldest }

    /// Top-5 clusters sorted by the user's chosen order.
    private var homeClusters: [PhotoCluster] {
        let base = library.filtered
        switch cardSort {
        case .oldest:
            return Array(base.sorted { ($0.anchorDate ?? .distantFuture) < ($1.anchorDate ?? .distantFuture) }.prefix(5))
        case .latest:
            return Array(base.sorted { ($0.anchorDate ?? .distantPast) > ($1.anchorDate ?? .distantPast) }.prefix(5))
        }
    }

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            content
        }
        .task {
            let status = library.authorizationStatus
            if status == .authorized || status == .limited {
                library.load()
            }
        }
        #if DEBUG
        .task(id: "iconExport") { AppIconExporter.exportIfNeeded() }
        #endif
        .onChange(of: library.clusters.count) {
            if currentIndex >= homeClusters.count {
                currentIndex = max(0, homeClusters.count - 1)
            }
        }
        .fullScreenCover(item: $reviewCluster, onDismiss: { library.load() }) { cluster in
            ReviewView(library: library, cluster: cluster)
        }
        .sheet(isPresented: $showBrowse) {
            BrowseView(library: library) { cluster in
                reviewCluster = cluster
            }
        }
        .sheet(isPresented: $showMap) {
            MapBrowseView(library: library) { cluster in
                reviewCluster = cluster
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(library: library)
        }
    }

    // MARK: - State routing

    @ViewBuilder
    private var content: some View {
        switch libraryState {
        case .onboarding: onboardingView
        case .denied:     deniedView
        case .loading:    loadingView
        case .empty:      allDoneView
        case .ready:
            GeometryReader { geo in
                mainView(geo: geo)
            }
        }
    }

    private enum LibraryState { case onboarding, denied, loading, empty, ready }

    private var libraryState: LibraryState {
        let s = library.authorizationStatus
        if s == .notDetermined { return .onboarding }
        if s == .denied || s == .restricted { return .denied }
        if library.isLoading { return .loading }
        if library.filtered.isEmpty { return .empty }
        return .ready
    }

    // MARK: - Main layout

    private func mainView(geo: GeometryProxy) -> some View {
        // Give the card everything except the fixed chrome above and below it.
        // Header ≈ 50pt + sort row ≈ 36pt + bottom section ≈ 124pt + paddings ≈ 44pt
        let reservedVertical: CGFloat = 254 + max(geo.safeAreaInsets.bottom, 24)
        let cardHeight = max(280, geo.size.height - reservedVertical)
        return VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 10)

            sortRow
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

            carousel(cardHeight: cardHeight)

            bottomStack
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, max(geo.safeAreaInsets.bottom, 24))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Spacer()

            Button { showSettings = true } label: {
                Image(systemName: "gear")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Settings")
        }
    }

    // MARK: - Sort row

    private var sortRow: some View {
        Button {
            currentIndex = 0
            sortRaw = cardSort == .oldest ? HomeCardSort.latest.rawValue : HomeCardSort.oldest.rawValue
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.caption2.weight(.semibold))
                Text(cardSort == .oldest ? "Oldest first" : "Latest first")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.white.opacity(0.35))
            .frame(height: 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Carousel

    private func carousel(cardHeight: CGFloat) -> some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(homeClusters.enumerated()), id: \.element.id) { i, cluster in
                MomentCard(cluster: cluster) {
                    reviewCluster = cluster
                }
                .padding(.horizontal, 20)
                .frame(height: cardHeight)
                .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: cardHeight)
        .id(sortRaw) // recreate when sort changes so index resets cleanly
    }

    // MARK: - Bottom stack (dots + CTA + secondary)

    private var bottomStack: some View {
        VStack(spacing: 10) {
            // Page dots — centered, only when there are multiple cards
            if homeClusters.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<homeClusters.count, id: \.self) { i in
                        Capsule()
                            .fill(i == currentIndex ? Color.accent : Color.white.opacity(0.25))
                            .frame(width: i == currentIndex ? 18 : 6, height: 6)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentIndex)
                    }
                }
                .padding(.bottom, 4)
            }

            // Browse by location — full-width row, only shown when geo data exists
            let hasGeo = library.filtered.contains { $0.firstLocationAsset?.location != nil }
            if hasGeo {
                Button { showMap = true } label: {
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Browse by location")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.30))
                    }
                    .foregroundStyle(Color.accent)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel("Browse by location")
            }

            // Browse all — full-width row with count on the right
            let count = library.toReviewCount
            Button { showBrowse = true } label: {
                HStack {
                    Text("Browse all")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text("\(count) moment\(count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.40))
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.30))
                }
                .foregroundStyle(Color.accent)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Browse all, \(count) moment\(count == 1 ? "" : "s")")
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 24) {
            Text("Faver")
                .font(.system(size: 48, weight: .bold, design: .serif))
                .foregroundStyle(.white)
            VStack(spacing: 6) {
                Text("Finding your moments…")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
                Text("Do yourself a favor.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.28))
            }
            ProgressView()
                .tint(Color.accent)
                .scaleEffect(1.3)
        }
    }

    // MARK: - Onboarding

    private var onboardingView: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Text("Faver")
                        .font(.system(size: 56, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                    Text("Do yourself a favor.")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                    Text("Make sure no moment\ngoes missing.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                }
                Button {
                    Task { await library.requestAccess() }
                } label: {
                    Text("Find my moments")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.accent, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(PressScaleStyle())
                .padding(.top, 8)
            }
            .padding(.horizontal, 36)
            Spacer()
        }
    }

    // MARK: - Denied

    private var deniedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.fill.on.rectangle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.white.opacity(0.35))
            Text("Photo access needed")
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(.white)
            Text("Enable access in Settings to use Faver.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(Color.accent, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(PressScaleStyle())
        }
        .padding(36)
    }

    // MARK: - All done

    private var allDoneView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 68))
                .foregroundStyle(Color.accent)
            Text("All caught up.")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(.white)
            Text("You've reviewed every moment\nin your library.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
            Button { showSettings = true } label: {
                Text("Adjust filters")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.accent)
            }
        }
        .padding(36)
    }
}

// MARK: - Moment card

/// A full-width photo card with gradient scrim, moment metadata, and an
/// embedded review button. The whole card is tappable — no separate CTA needed.
private struct MomentCard: View {
    let cluster: PhotoCluster
    let onTap: () -> Void

    @State private var thumbnails: [UIImage] = []
    @State private var locationName: String? = nil

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottom) {
                collage.clipShape(RoundedRectangle(cornerRadius: 24))

                // Gradient scrim — extended lower to cover the button area
                LinearGradient(
                    stops: [
                        .init(color: .clear,               location: 0.18),
                        .init(color: .black.opacity(0.88),  location: 1.0)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 24))

                // Content overlay: title + metadata + embedded CTA
                VStack(alignment: .leading, spacing: 6) {
                    Text(cluster.title)
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text(cluster.dateLabel)
                        if let place = locationName {
                            Text("·")
                            Text(place)
                        }
                        Text("·")
                        Text("\(cluster.count) photos")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)

                    // Review button — lives inside the card so card + action are one unit
                    HStack(spacing: 8) {
                        Image(systemName: "heart.fill")
                        Text("Review this moment")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Color.accent, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.bottom, 20)
            }
        }
        .buttonStyle(PressScaleStyle())
        .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 10)
        .task(id: cluster.id) {
            await loadThumbnails()
            locationName = await GeocodingCache.shared.lookup(cluster.firstLocationAsset?.location)
        }
    }

    // MARK: Collage

    @ViewBuilder
    private var collage: some View {
        GeometryReader { geo in
            if thumbnails.isEmpty {
                Rectangle().fill(Color.surface)
            } else if thumbnails.count == 1 {
                photoCell(thumbnails[0])
            } else if thumbnails.count == 2 {
                HStack(spacing: 1) {
                    photoCell(thumbnails[0]).frame(width: geo.size.width * 0.62)
                    photoCell(thumbnails[1])
                }
            } else {
                // Hero on top, two supporting photos below
                VStack(spacing: 1) {
                    photoCell(thumbnails[0])
                        .frame(height: geo.size.height * 0.62)
                    HStack(spacing: 1) {
                        photoCell(thumbnails[1])
                        photoCell(thumbnails[2])
                    }
                }
            }
        }
    }

    private func photoCell(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }

    // MARK: Thumbnail loading

    private func loadThumbnails() async {
        let assets = Array(cluster.assetsToReview.prefix(3))

        // Phase 1 — fast local previews: get something on screen immediately.
        var result: [Int: UIImage] = [:]
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for (i, asset) in assets.enumerated() {
                group.addTask { (i, await Self.thumbnail(for: asset, targetSize: CGSize(width: 400, height: 400))) }
            }
            for await (i, img) in group {
                if let img {
                    result[i] = img
                    thumbnails = (0..<assets.count).compactMap { result[$0] }
                }
            }
        }

        // Phase 2 — high-res upgrade: replace each thumbnail as the sharp version arrives.
        // Uses a larger target and highQualityFormat (still no network, so iCloud-only
        // photos fall back gracefully to whatever is cached locally).
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for (i, asset) in assets.enumerated() {
                group.addTask { (i, await Self.thumbnail(for: asset, targetSize: CGSize(width: 1200, height: 1200))) }
            }
            for await (i, img) in group {
                guard let img else { continue }
                result[i] = img
                thumbnails = (0..<assets.count).compactMap { result[$0] }
            }
        }
    }

    private static func thumbnail(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let opts = PHImageRequestOptions()
            opts.isNetworkAccessAllowed = false  // never stall waiting for iCloud
            opts.resizeMode = .fast
            // .opportunistic for the small pass (fast degraded preview then final),
            // .highQualityFormat for the large pass (one call, best local quality).
            opts.deliveryMode = targetSize.width <= 400 ? .opportunistic : .highQualityFormat
            nonisolated(unsafe) var done = false
            nonisolated(unsafe) var fallback: UIImage? = nil
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: opts
            ) { img, info in
                guard !done else { return }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded { fallback = img; return }
                done = true
                continuation.resume(returning: img ?? fallback)
            }
        }
    }
}
