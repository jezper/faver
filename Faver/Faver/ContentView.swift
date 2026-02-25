import Photos
import SwiftUI

// MARK: - Theme

extension Color {
    /// Faver's signature warm amber — tint, progress bars, CTAs.
    static let faver = Color(red: 0.925, green: 0.494, blue: 0.188)
    /// Darker amber for text on light backgrounds — passes WCAG AA (6.4:1 on faverBackground).
    static let faverDark = Color(red: 0.58, green: 0.24, blue: 0.04)
    /// Warm cream app background — pairs with amber accent and photo cards.
    static let faverBackground = Color(red: 0.976, green: 0.963, blue: 0.945)
    /// Warm amber-tinted shadow colour (use .opacity() inline).
    static let faverShadow = Color(red: 0.65, green: 0.35, blue: 0.06)
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var photoLibrary = PhotoLibraryService()
    @State private var showingMap = false
    @State private var showingSettings = false
    @State private var showingProgressInfo = false
    @State private var suggestionIndex = 0
    @State private var selectedHeroCluster: PhotoCluster?

    var progressPercent: Int {
        guard photoLibrary.totalCount > 0 else { return 0 }
        let done = photoLibrary.totalCount - photoLibrary.toReviewCount
        return Int((Double(done) / Double(photoLibrary.totalCount)) * 100)
    }

    private var progressExplainer: String {
        let done = photoLibrary.totalCount - photoLibrary.toReviewCount
        return "\(done) of \(photoLibrary.totalCount) photos don't need review — either because you've already seen them, or because their moment already has at least one favorite. The remaining \(photoLibrary.toReviewCount) are waiting in your sets."
    }

    var body: some View {
        Group {
            switch photoLibrary.authorizationStatus {
            case .authorized, .limited:
                libraryView
            case .denied, .restricted:
                deniedView
            default:
                welcomeView
            }
        }
        .fontDesign(.default)
        .tint(.faver)
        .background(Color.faverBackground.ignoresSafeArea())
    }

    // MARK: - Library

    private var libraryView: some View {
        NavigationStack {
            libraryContent
                .background(Color.faverBackground)
                .navigationTitle("Faver")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Color.faverBackground, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gear")
                        }
                        .accessibilityLabel("Settings")
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { showingProgressInfo = true } label: {
                            Text("\(progressPercent)% reviewed")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Color.faver)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.faver.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        .accessibilityLabel("\(progressPercent) percent of library reviewed. Double tap for details.")
                    }
                }
                .navigationDestination(for: Int.self) { year in
                    YearView(year: year, photoLibrary: photoLibrary)
                }
                .alert("Your progress", isPresented: $showingProgressInfo) {
                    Button("Got it", role: .cancel) {}
                } message: {
                    Text(progressExplainer)
                }
        }
        .sheet(isPresented: $showingMap) {
            MapBrowseView(photoLibrary: photoLibrary)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(photoLibrary: photoLibrary)
        }
        .task { photoLibrary.loadAssets() }
    }

    @ViewBuilder
    private var libraryContent: some View {
        if photoLibrary.isLoading {
            loadingView
        } else if photoLibrary.years.isEmpty && !photoLibrary.clusters.isEmpty {
            filteredEmptyView
        } else if photoLibrary.years.isEmpty {
            allDoneView
        } else {
            mainLibraryView
        }
    }

    // MARK: - Main library (new hero layout)

    private var mainLibraryView: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    heroSection(screenHeight: geo.size.height)
                    browseSection
                }
                .padding(.bottom, 40)
            }
        }
        .background(Color.faverBackground)
        .fullScreenCover(item: $selectedHeroCluster, onDismiss: {
            photoLibrary.loadAssets()
            suggestionIndex = 0
        }) { cluster in
            ReviewView(photoLibrary: photoLibrary, assets: cluster.assetsToReview)
        }
    }

    // MARK: - Hero

    private func heroSection(screenHeight: CGFloat) -> some View {
        let suggestions = photoLibrary.suggestedClusters
        let cluster = suggestionIndex < suggestions.count ? suggestions[suggestionIndex] : suggestions.first

        return ZStack(alignment: .bottom) {
            // Photo background
            if let asset = cluster?.assetsToReview.first {
                HeroPhotoView(asset: asset)
                    .id(cluster?.id)
                    .transition(.opacity)
            } else {
                Rectangle().fill(Color(red: 0.84, green: 0.80, blue: 0.74))
            }

            // Gradient scrim — deep enough for legible text on any photo
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.25),
                    .init(color: .black.opacity(0.88), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Info + CTA
            VStack(alignment: .leading, spacing: 0) {
                Text("suggested for you".uppercased())
                    .font(.system(size: 10, weight: .bold, design: .serif))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.bottom, 10)

                Text(cluster?.title ?? "")
                    .font(.system(size: 30, weight: .black, design: .serif))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
                    .lineLimit(2)
                    .padding(.bottom, 6)

                HStack(spacing: 5) {
                    Text(cluster?.dateLabel ?? "")
                    Text("·")
                    Text("\(cluster?.count ?? 0) to review")
                }
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .padding(.bottom, 24)

                Button(action: {
                    if let c = cluster {
                        withAnimation(.spring(response: 0.3)) { selectedHeroCluster = c }
                    }
                }) {
                    HStack(spacing: 8) {
                        Text("Review now")
                            .font(.body.weight(.semibold))
                        Image(systemName: "arrow.right")
                            .font(.body.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color.faver)
                    .clipShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())

                // Page-dot strip — only shown if there are multiple suggestions
                if suggestions.count > 1 {
                    HStack(spacing: 5) {
                        ForEach(0..<min(suggestions.count, 5), id: \.self) { i in
                            Capsule()
                                .fill(i == suggestionIndex
                                      ? Color.white
                                      : Color.white.opacity(0.35))
                                .frame(width: i == suggestionIndex ? 16 : 6, height: 6)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7),
                                           value: suggestionIndex)
                        }
                    }
                    .padding(.top, 14)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .frame(height: screenHeight * 0.68)
        .animation(.easeInOut(duration: 0.35), value: suggestionIndex)
        // Horizontal swipe cycles through top suggestions
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    if value.translation.width < -40, suggestionIndex < suggestions.count - 1 {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { suggestionIndex += 1 }
                    } else if value.translation.width > 40, suggestionIndex > 0 {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { suggestionIndex -= 1 }
                    }
                }
        )
    }

    // MARK: - Browse section

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("Your library")
                    .font(.system(size: 22, weight: .black, design: .serif))
                Spacer()
                Button(action: { showingMap = true }) {
                    Label("Map", systemImage: "map.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.faver)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 32)
            .padding(.bottom, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(photoLibrary.years) { summary in
                        NavigationLink(value: summary.year) {
                            MiniYearCard(
                                summary: summary,
                                sampleAssets: photoLibrary.sampleAssets(for: summary.year)
                            )
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel("\(summary.year), \(summary.clusterCount) moments, \(summary.toReviewCount) to review")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Other states

    private var loadingView: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 6) {
                Text("Faver")
                    .font(.system(size: 56, weight: .black, design: .serif))
                Text("Find the moments worth keeping.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 10) {
                ProgressView(value: photoLibrary.scanProgress)
                    .progressViewStyle(.linear)
                    .tint(.faver)
                    .frame(maxWidth: 220)
                    .animation(.easeInOut(duration: 0.3), value: photoLibrary.scanProgress)
                Text(photoLibrary.scanProgress < 0.87 ? "Scanning library…" : "Grouping into moments…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var welcomeView: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 8) {
                Text("Faver")
                    .font(.system(size: 68, weight: .black, design: .serif))
                Text("Find the moments\nworth keeping.")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Group {
                if photoLibrary.isLoading {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Setting up…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button("Get started") {
                        Task { await photoLibrary.requestAccess() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.bottom, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }

    private var filteredEmptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No sets match your filter")
                .font(.title2.weight(.bold))
            Text("Lower the minimum set size in Settings to see more moments.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Open Settings") { showingSettings = true }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .padding()
    }

    private var allDoneView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.faver)
            Text("All reviewed!")
                .font(.title2.weight(.bold))
            Text("Your entire library has been gone through.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var deniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Photo access required")
                .font(.title2)
            Text("Go to Settings → Faver to allow access.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

// MARK: - HeroPhotoView

private struct HeroPhotoView: View {
    let asset: PHAsset
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                Rectangle().fill(Color(red: 0.84, green: 0.80, blue: 0.74))
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
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 600, height: 900),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}

// MARK: - MiniYearCard

private struct MiniYearCard: View {
    let summary: YearSummary
    let sampleAssets: [PHAsset]
    @State private var thumbnails: [UIImage] = []

    var body: some View {
        ZStack(alignment: .bottom) {
            // Photo collage (up to 2 photos)
            if thumbnails.isEmpty {
                Rectangle().fill(Color(red: 0.84, green: 0.80, blue: 0.74))
            } else if thumbnails.count == 1 {
                photoCell(thumbnails[0])
            } else {
                HStack(spacing: 2) {
                    photoCell(thumbnails[0])
                    photoCell(thumbnails[1])
                }
            }

            // Gradient scrim
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.2),
                    .init(color: .black.opacity(0.78), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Year + count
            VStack(alignment: .leading, spacing: 2) {
                Text(String(summary.year))
                    .font(.system(size: 26, weight: .black, design: .serif))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)
                Text("\(summary.toReviewCount) to review")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .frame(width: 130, height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.faverShadow.opacity(0.18), radius: 12, x: 0, y: 5)
        .task(id: summary.id) { await loadThumbnails() }
    }

    @ViewBuilder
    private func photoCell(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }

    private func loadThumbnails() async {
        let assets = Array(sampleAssets.prefix(2))
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
                targetSize: CGSize(width: 200, height: 250),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}

// MARK: - PressableButtonStyle

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

#Preview {
    ContentView()
}
