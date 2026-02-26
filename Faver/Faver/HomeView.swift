import Photos
import SwiftUI

// MARK: - Home screen

struct HomeView: View {
    @StateObject private var library = PhotoLibrary()
    @State private var currentIndex: Int = 0
    @State private var reviewCluster: PhotoCluster? = nil
    @State private var showBrowse = false
    @State private var showSettings = false

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
        .onChange(of: library.suggested.count) {
            if currentIndex >= library.suggested.count {
                currentIndex = max(0, library.suggested.count - 1)
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
        if library.suggested.isEmpty { return .empty }
        return .ready
    }

    // MARK: - Main layout

    private func mainView(geo: GeometryProxy) -> some View {
        let cardHeight = geo.size.height * 0.56
        return VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 14)

            carousel(cardHeight: cardHeight)

            Spacer(minLength: 10)

            bottomStack
                .padding(.horizontal, 20)
                .padding(.bottom, max(geo.safeAreaInsets.bottom, 24))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Faver")
                .font(.system(size: 30, weight: .bold, design: .serif))
                .foregroundStyle(.white)

            Spacer()

            let pct = Int(library.reviewedFraction * 100)
            Text("\(pct)% reviewed")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.accentDim, in: Capsule())

            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Settings")
        }
    }

    // MARK: - Carousel

    private func carousel(cardHeight: CGFloat) -> some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(library.suggested.enumerated()), id: \.element.id) { i, cluster in
                MomentCard(cluster: cluster)
                    .padding(.horizontal, 20)
                    .frame(height: cardHeight)
                    .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: cardHeight)
    }

    // MARK: - Bottom stack (dots + CTA + secondary)

    private var bottomStack: some View {
        VStack(spacing: 14) {
            // Page dots
            if library.suggested.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<library.suggested.count, id: \.self) { i in
                        Capsule()
                            .fill(i == currentIndex ? Color.accent : Color.white.opacity(0.25))
                            .frame(width: i == currentIndex ? 18 : 6, height: 6)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentIndex)
                    }
                }
            }

            // Review CTA
            Button {
                if let c = library.suggested[safe: currentIndex] {
                    reviewCluster = c
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill")
                    Text("Review this moment")
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.accent, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(PressScaleStyle())

            // Browse link
            Button { showBrowse = true } label: {
                let count = library.toReviewCount
                Text("\(count) moment\(count == 1 ? "" : "s") waiting · Browse all →")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 24) {
            Text("Faver")
                .font(.system(size: 48, weight: .bold, design: .serif))
                .foregroundStyle(.white)
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
                VStack(spacing: 10) {
                    Text("Faver")
                        .font(.system(size: 56, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                    Text("One great photo\nfrom every moment.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                Button {
                    Task { await library.requestAccess() }
                } label: {
                    Text("Get started")
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
            Text("All caught up!")
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

/// A full-width photo card with gradient scrim and moment metadata.
private struct MomentCard: View {
    let cluster: PhotoCluster

    @State private var thumbnails: [UIImage] = []
    @State private var locationName: String? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            collage.clipShape(RoundedRectangle(cornerRadius: 24))

            // Gradient scrim
            LinearGradient(
                stops: [
                    .init(color: .clear,              location: 0.28),
                    .init(color: .black.opacity(0.88), location: 1.0)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 24))

            // Text overlay
            VStack(alignment: .leading, spacing: 7) {
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.bottom, 26)
        }
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
                HStack(spacing: 2) {
                    photoCell(thumbnails[0])
                    photoCell(thumbnails[1])
                }
            } else {
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
        var indexed: [(Int, UIImage)] = []
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for (i, asset) in assets.enumerated() {
                group.addTask { (i, await Self.thumbnail(for: asset)) }
            }
            for await (i, img) in group {
                if let img { indexed.append((i, img)) }
            }
        }
        thumbnails = indexed.sorted { $0.0 < $1.0 }.map { $0.1 }
    }

    private static func thumbnail(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .highQualityFormat
            opts.resizeMode = .fast
            opts.isNetworkAccessAllowed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 400, height: 400),
                contentMode: .aspectFill,
                options: opts
            ) { img, _ in continuation.resume(returning: img) }
        }
    }
}
