import Photos
import SwiftUI

/// Full-screen, immersive photo review for a single moment.
/// Swipe freely through all photos; tap the heart to toggle each one.
/// After the last photo, one more swipe reveals a completion page.
///
/// Swiping spends nothing. A moment is marked reviewed by the last step at the end of
/// it, all at once, and never before — open one, look at two photos, leave, and it is
/// exactly as it was. What is remembered instead is the position, so the next visit opens
/// on the photo the user stopped at. Leaving therefore needs no confirmation: nothing is
/// lost by going.
///
/// In `revisiting` mode the moment comes from the archive and shows every photo it has,
/// not just what is left, so a decision can be looked at again.
struct ReviewView: View {
    let library: LibraryService
    let cluster: PhotoCluster
    let revisiting: Bool

    /// The pager's positions. Built once, here, rather than recomputed on every render.
    private let units: [ReviewUnit]

    init(library: LibraryService, cluster: PhotoCluster, revisiting: Bool = false) {
        self.library = library
        self.cluster = cluster
        self.revisiting = revisiting
        let units = revisiting ? groupIntoUnits(cluster.allAssets) : cluster.units
        self.units = units

        // Opening straight onto the remembered photo, rather than jumping there after the
        // first frame has already drawn the wrong one. Found by looking for the marked
        // photo among these units, so it still works when the grouping settings have been
        // changed since and this is not the same moment it was.
        let start = units.firstIndex { unit in
            unit.assets.contains { ReviewStore.shared.isStop($0.localIdentifier) }
        } ?? 0
        _currentPage = State(initialValue: start)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentPage: Int = 0
    @State private var favoritedIDs: Set<String> = []
    @State private var failureNotice: String? = nil
    /// Which photo is showing inside each burst, keyed by the burst's id.
    @State private var burstPosition: [String: String] = [:]

    private let haptics = UIImpactFeedbackGenerator(style: .medium)

    private var isOnCompletionPage: Bool { currentPage == units.count }
    private var currentUnit: ReviewUnit? { units[safe: currentPage] }

    /// The photo the favorite button acts on: the one showing inside the current burst,
    /// or the only one if this position is a single photo.
    private var currentAsset: PHAsset? {
        guard let unit = currentUnit else { return nil }
        if let id = burstPosition[unit.id],
           let asset = unit.assets.first(where: { $0.localIdentifier == id }) {
            return asset
        }
        return unit.assets.first
    }
    private var isCurrentFavorited: Bool {
        favoritedIDs.contains(currentAsset?.localIdentifier ?? "")
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Photo pager + completion page
            TabView(selection: $currentPage) {
                ForEach(Array(units.enumerated()), id: \.element.id) { i, unit in
                    unitPage(unit)
                        .tag(i)
                        .ignoresSafeArea()
                }
                completionPage
                    .tag(units.count)
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

            if let failureNotice {
                VStack {
                    Spacer()
                    Text(failureNotice)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .glassEffect(.regular, in: Capsule())
                        .padding(.bottom, 150)
                }
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
        .animation(.calm(reduceMotion: reduceMotion), value: failureNotice)
        // Clears itself. A failed favourite is worth saying once, not worth a dialog
        // the user has to dismiss before carrying on.
        .task(id: failureNotice) {
            guard failureNotice != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { failureNotice = nil }
        }
        .statusBarHidden()
        .task {
            // Seed from any photos already favorited in this cluster
            let ids = cluster.assetsToReview
                .filter { $0.isFavorite }
                .map { $0.localIdentifier }
            favoritedIDs = Set(ids)
            // Opening finishes nothing. It records that Faver has been in here, which is
            // the only thing separating a moment being curated now from one curated by
            // hand years before the app existed.
            if !revisiting { library.markVisited(cluster) }
        }
        // Remembering where the user is, not spending anything. Recorded here rather than
        // in the pager's ForEach because the paging TabView builds the neighbouring pages
        // before they are ever shown.
        .onChange(of: currentPage) { _, page in rememberPosition(page) }
    }

    // MARK: - One position in the pager

    @ViewBuilder
    private func unitPage(_ unit: ReviewUnit) -> some View {
        if unit.isBurst {
            ZStack(alignment: .trailing) {
                // A vertical paging ScrollView rather than a rotated TabView. SwiftUI's
                // page style only runs horizontally, and the rotation trick breaks the
                // zoom gesture inside each photo.
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(unit.assets, id: \.localIdentifier) { asset in
                            media(for: asset)
                                .containerRelativeFrame([.horizontal, .vertical])
                                .id(asset.localIdentifier)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollIndicators(.hidden)
                .scrollPosition(id: burstBinding(for: unit))

                burstRail(unit)
            }
        } else if let asset = unit.assets.first {
            media(for: asset)
        }
    }

    @ViewBuilder
    private func media(for asset: PHAsset) -> some View {
        if asset.mediaType == .video {
            VideoReviewView(asset: asset)
        } else {
            ZoomableImageView(asset: asset)
        }
    }

    /// A column of marks down the trailing edge. It says, without a word of instruction,
    /// that this position holds more than one photo and that they are stacked vertically.
    private func burstRail(_ unit: ReviewUnit) -> some View {
        let currentID = burstPosition[unit.id] ?? unit.assets.first?.localIdentifier
        return VStack(spacing: 5) {
            ForEach(unit.assets, id: \.localIdentifier) { asset in
                let isCurrent = asset.localIdentifier == currentID
                Capsule()
                    .fill(isCurrent ? Color.white : Color.white.opacity(0.4))
                    .frame(width: 3, height: isCurrent ? 16 : 6)
                    .animation(.calm(reduceMotion: reduceMotion), value: currentID)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .glassEffect(.regular, in: Capsule())
        .padding(.trailing, 14)
        .accessibilityElement()
        .accessibilityLabel("\(unit.assets.count) photos taken together. Swipe up and down to see them.")
    }

    private func burstBinding(for unit: ReviewUnit) -> Binding<String?> {
        Binding(
            get: { burstPosition[unit.id] ?? unit.assets.first?.localIdentifier },
            set: { burstPosition[unit.id] = $0 ?? unit.assets.first?.localIdentifier }
        )
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
                .accessibilityIdentifier("done")

                Spacer()

                let total = units.count
                if total > 1 {
                    Text("\(min(currentPage + 1, total)) / \(total)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: Capsule())
                        .accessibilityLabel("Item \(min(currentPage + 1, total)) of \(total)")
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
            .accessibilityIdentifier("favorite")
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
                    Image(systemName: revisiting ? "clock.arrow.circlepath" : (favoritedIDs.isEmpty ? "checkmark.circle" : "heart.fill"))
                        .font(.system(size: 56))
                        .foregroundStyle(Color.accent)

                    VStack(spacing: 10) {
                        Text(revisiting ? "That's the whole moment." : "You've been through them all.")
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
                        if revisiting { dismiss() } else { markMomentReviewed(); dismiss() }
                    } label: {
                        Text(revisiting ? "Done" : "Mark as reviewed")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 56)
                            .background(Color.accent, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityIdentifier("finish-moment")

                    Button {
                        if revisiting { library.reviewAgain(cluster) }
                        dismiss()
                    } label: {
                        // From the archive this is the way back into the queue, so the
                        // moment turns up on its own again rather than only when the user
                        // remembers to go looking for it.
                        Text(revisiting ? "Put back in the queue" : "Come back to this")
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

    private var momentAssetIDs: [String] { cluster.allAssets.map(\.localIdentifier) }

    private func rememberPosition(_ page: Int) {
        guard !revisiting, let unit = units[safe: page], let first = unit.assets.first else { return }
        ReviewStore.shared.setStop(first.localIdentifier, within: momentAssetIDs)
    }

    /// The one place a moment becomes reviewed. All of it, at once, on purpose.
    private func markMomentReviewed() {
        library.markMomentReviewed(cluster)
    }

    private func toggleFavorite() {
        guard let asset = currentAsset else { return }
        haptics.impactOccurred()
        let id = asset.localIdentifier
        let turningOn = !favoritedIDs.contains(id)

        // The heart moves first, because the toggle has to feel instant. The write is
        // then checked, and put back if the photo library refused it.
        if turningOn { favoritedIDs.insert(id) } else { favoritedIDs.remove(id) }

        Task {
            let saved = await library.favorite(asset, on: turningOn)
            guard !saved else { return }
            if turningOn { favoritedIDs.remove(id) } else { favoritedIDs.insert(id) }
            failureNotice = turningOn
                ? "Couldn't save that favourite."
                : "Couldn't remove that favourite."
        }
    }

    private func done() {
        // Nothing to confirm. Every photo the user reached is already recorded, and
        // the moment they leave behind keeps exactly the photos they have not seen.
        dismiss()
    }
}

