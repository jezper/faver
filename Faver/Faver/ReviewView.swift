import Photos
import SwiftUI

/// Full-screen, immersive photo review for a single moment.
/// Swipe freely through all photos; tap the heart to toggle each one.
/// After the last photo, one more swipe reveals a completion page.
///
/// Every photo is recorded as seen the moment it is the one on screen, so leaving is
/// always free: the next visit rebuilds the moment out of what is left, which lands
/// the user on exactly the photo they stopped at. Nothing needs to be confirmed on
/// the way out, because nothing is lost by going.
struct ReviewView: View {
    let library: LibraryService
    let cluster: PhotoCluster

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentPage: Int = 0
    @State private var favoritedIDs: Set<String> = []

    private let haptics = UIImpactFeedbackGenerator(style: .medium)

    private var isOnCompletionPage: Bool { currentPage == cluster.assetsToReview.count }
    private var currentAsset: PHAsset? { cluster.assetsToReview[safe: currentPage] }
    private var isCurrentFavorited: Bool {
        favoritedIDs.contains(currentAsset?.localIdentifier ?? "")
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Photo pager + completion page
            TabView(selection: $currentPage) {
                ForEach(Array(cluster.assetsToReview.enumerated()), id: \.element.localIdentifier) { i, asset in
                    Group {
                        if asset.mediaType == .video {
                            VideoReviewView(asset: asset)
                        } else {
                            ZoomableImageView(asset: asset)
                        }
                    }
                    .tag(i)
                    .ignoresSafeArea()
                }
                completionPage
                    .tag(cluster.assetsToReview.count)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            // Standard HUD — hidden on the completion page (which has its own actions)
            if !isOnCompletionPage {
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    bottomBar
                }
                .ignoresSafeArea(edges: .bottom)
            }

        }
        .statusBarHidden()
        .task {
            // Seed from any photos already favorited in this cluster
            let ids = cluster.assetsToReview
                .filter { $0.isFavorite }
                .map { $0.localIdentifier }
            favoritedIDs = Set(ids)
            markCurrentSeen()
        }
        // Recorded per page rather than in the pager's ForEach: the paging TabView
        // builds the neighbouring pages before they are ever shown, so marking on
        // their appearance would count photos the user never actually looked at.
        .onChange(of: currentPage) { _, _ in markCurrentSeen() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack {
                Button { done() } label: {
                    Text("Done")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .glassEffect(.regular.interactive(), in: Capsule())
                .accessibilityLabel("Done reviewing")

                Spacer()

                let total = cluster.assetsToReview.count
                if total > 1 {
                    Text("\(currentPage + 1) / \(total)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: Capsule())
                        .accessibilityLabel("Photo \(currentPage + 1) of \(total)")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        // Glass resolves whatever is behind it, and a white sky is the one thing it
        // cannot separate itself from. A short wash keeps the controls readable over
        // a bright horizon without reading as a bar across the photo.
        .background(
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.3), location: 0),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        )
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 44) // gradient height above button

            Button { toggleFavorite() } label: {
                // Favorited is carried three ways at once — the button fills warm red,
                // the outline fills in, and the symbol changes shape — so it still reads
                // for someone who cannot tell the colours apart, and it survives the
                // system transparency setting being dragged all the way to clear.
                Image(systemName: isCurrentFavorited ? "heart.fill" : "heart")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .animation(.calm(reduceMotion: reduceMotion), value: isCurrentFavorited)
                    .frame(width: 64, height: 64)
            }
            .glassEffect(
                isCurrentFavorited
                    ? .regular.tint(Color.heart).interactive()
                    : .regular.interactive(),
                in: Circle()
            )
            .accessibilityLabel(isCurrentFavorited ? "Remove from favorites" : "Add to favorites")
            .padding(.bottom, 44)
        }
        .frame(maxWidth: .infinity)
        // Lighter and shorter than it was. Glass now carries the legibility, so the
        // scrim no longer has to stamp a black band across the bottom of every photo.
        .background(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.45), location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        )
    }

    // MARK: - Completion page

    private var completionPage: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 20) {
                    // Icon reflects whether any photos were favorited
                    Image(systemName: favoritedIDs.isEmpty ? "checkmark.circle" : "heart.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.accent)

                    VStack(spacing: 10) {
                        Text("You've been through them all.")
                            .font(.system(.title, design: .serif).weight(.bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)

                        Group {
                            if favoritedIDs.isEmpty {
                                Text("Nothing stood out — that's fine too.")
                            } else {
                                let n = favoritedIDs.count
                                Text("You marked \(n) \(n == 1 ? "photo" : "photos") as a favourite.")
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                    }
                }

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        cluster.assetsToReview.forEach { library.markSeen($0) }
                        dismiss()
                    } label: {
                        Text("Mark as reviewed")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 56)
                            .background(Color.accent, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(PressScaleStyle())

                    Button { dismiss() } label: {
                        Text("Come back to this")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 56)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Actions

    private func markCurrentSeen() {
        guard let asset = currentAsset else { return }
        library.markSeen(asset)
    }

    private func toggleFavorite() {
        guard let asset = currentAsset else { return }
        haptics.impactOccurred()
        let id = asset.localIdentifier
        if favoritedIDs.contains(id) {
            favoritedIDs.remove(id)
            library.favorite(asset, on: false)
        } else {
            favoritedIDs.insert(id)
            library.favorite(asset, on: true)
        }
    }

    private func done() {
        // Nothing to confirm. Every photo the user reached is already recorded, and
        // the moment they leave behind keeps exactly the photos they have not seen.
        dismiss()
    }
}

