import Photos
import SwiftUI

// MARK: - Theme

extension Color {
    /// Faver's signature warm amber — tint, progress bars, CTAs.
    static let faver = Color(red: 0.925, green: 0.494, blue: 0.188)
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
    @State private var listAppeared = false

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
                .navigationBarTitleDisplayMode(.large)
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
            ScrollView {
                VStack(spacing: 0) {
                    // Location browse button
                    Button(action: { showingMap = true }) {
                        HStack(spacing: 10) {
                            Image(systemName: "map.fill")
                                .font(.body)
                                .foregroundStyle(.tint)
                            Text("Browse by location")
                                .font(.body)
                                .foregroundStyle(.tint)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: Color.faverShadow.opacity(0.12), radius: 12, x: 0, y: 4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                    // Year cards — photo-forward, newest first
                    LazyVStack(spacing: 14) {
                        ForEach(Array(photoLibrary.years.enumerated()), id: \.element.id) { index, summary in
                            NavigationLink(value: summary.year) {
                                YearCard(
                                    summary: summary,
                                    sampleAssets: photoLibrary.sampleAssets(for: summary.year)
                                )
                            }
                            .buttonStyle(PressableButtonStyle())
                            .accessibilityLabel("\(summary.year), \(summary.clusterCount) sets, \(summary.toReviewCount) photos to review")
                            .opacity(listAppeared ? 1 : 0)
                            .offset(y: listAppeared ? 0 : 28)
                            .animation(
                                .spring(response: 0.55, dampingFraction: 0.82)
                                    .delay(Double(index) * 0.055),
                                value: listAppeared
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                    .onAppear {
                        listAppeared = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            listAppeared = true
                        }
                    }
                }
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
            // Shows a spinner while iOS initialises the Photos framework
            // (can take 5-10 s on first authorisation before our progress bar appears)
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

// MARK: - YearCard

private struct YearCard: View {
    let summary: YearSummary
    let sampleAssets: [PHAsset]

    @State private var thumbnails: [UIImage] = []

    var body: some View {
        ZStack(alignment: .bottom) {
            // Full-bleed photo mosaic
            collage

            // Liquid Glass info strip
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(summary.year))
                        .font(.system(size: 52, weight: .black, design: .serif))
                        .foregroundStyle(.white)
                    Text("\(summary.clusterCount) moments · \(summary.toReviewCount) to review")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .glassEffect(in: RoundedRectangle(cornerRadius: 6))
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: Color.faverShadow.opacity(0.22), radius: 20, x: 0, y: 8)
        .task(id: summary.id) { await loadThumbnails() }
    }

    // MARK: - Collage

    @ViewBuilder
    private var collage: some View {
        GeometryReader { geo in
            if thumbnails.isEmpty {
                Rectangle().fill(Color(red: 0.84, green: 0.80, blue: 0.74))
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
        let assets = Array(sampleAssets.prefix(3))
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
                targetSize: CGSize(width: 320, height: 320),
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
