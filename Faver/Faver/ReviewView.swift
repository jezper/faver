import Photos
import SwiftUI

/// Full-screen, immersive photo review for a single moment.
/// Swipe freely through all photos; tap the heart to toggle each one.
/// After the last photo, one more swipe reveals a completion page where the
/// user explicitly marks the moment as reviewed — or keeps it for later.
struct ReviewView: View {
    let library: LibraryService
    let cluster: PhotoCluster

    @Environment(\.dismiss) private var dismiss
    @State private var currentPage: Int = 0
    @State private var favoritedIDs: Set<String> = []
    @State private var showEarlyExitSheet = false

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
                    ZoomableImageView(asset: asset)
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

            // Early-exit overlay — slides up when user taps Done before finishing
            if showEarlyExitSheet {
                earlyExitOverlay
                    .transition(.opacity)
            }
        }
        .statusBarHidden()
        .task {
            // Seed from any photos already favorited in this cluster
            let ids = cluster.assetsToReview
                .filter { $0.isFavorite }
                .map { $0.localIdentifier }
            favoritedIDs = Set(ids)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button { done() } label: {
                Text("Done")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .accessibilityLabel("Done reviewing")

            Spacer()

            let total = cluster.assetsToReview.count
            if total > 1 {
                Text("\(currentPage + 1) / \(total)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 60) // gradient height above button

            Button { toggleFavorite() } label: {
                Image(systemName: isCurrentFavorited ? "heart.fill" : "heart")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(isCurrentFavorited ? Color.heart : .white)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isCurrentFavorited)
                    .frame(width: 64, height: 64)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel(isCurrentFavorited ? "Remove from favorites" : "Add to favorites")
            .padding(.bottom, 44)
        }
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.75), location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
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
                            .font(.system(size: 26, weight: .bold, design: .serif))
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
                        .foregroundStyle(.white.opacity(0.55))
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
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.accent, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(PressScaleStyle())

                    Button { dismiss() } label: {
                        Text("Come back to this")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.45))
                            .padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 56)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Early exit overlay

    private var earlyExitOverlay: some View {
        ZStack(alignment: .bottom) {
            // Scrim — tap to cancel
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        showEarlyExitSheet = false
                    }
                }

            // Bottom panel
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("Leave this moment?")
                        .font(.system(size: 20, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                    Text("You haven't seen every photo yet.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                }

                // Primary action — keep browsing later
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        showEarlyExitSheet = false
                    }
                    dismiss()
                } label: {
                    Text("Keep for later")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.accent, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(PressScaleStyle())

                // Deliberate action — slide to mark all as reviewed
                SlideToConfirm(label: "Slide to mark as reviewed") {
                    cluster.assetsToReview.forEach { library.markSeen($0) }
                    dismiss()
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 44)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        }
        .ignoresSafeArea()
    }

    // MARK: - Actions

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
        // Guard: the user must reach the completion page to mark a set as handled.
        // Pressing Done on any photo page shows the exit sheet instead of silently dismissing.
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            showEarlyExitSheet = true
        }
    }
}

// MARK: - Slide to confirm

/// Full-width draggable track. Drag the thumb ≥ 80 % to the right to fire the action.
/// Releases below the threshold spring back to the left.
private struct SlideToConfirm: View {
    let label: String
    let action: () -> Void

    @State private var dragOffset: CGFloat = 0
    private let trackHeight: CGFloat = 56
    private let thumbSize:   CGFloat = 44

    var body: some View {
        GeometryReader { geo in
            let maxDrag = geo.size.width - thumbSize - 12
            let progress = maxDrag > 0 ? max(0, min(1, dragOffset / maxDrag)) : 0

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .frame(height: trackHeight)

                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(max(0, 0.6 - progress * 0.6)))
                    .frame(maxWidth: .infinity)
                    .frame(height: trackHeight)

                Circle()
                    .fill(Color.accent)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: 6 + dragOffset)
                    .shadow(color: Color.accent.opacity(0.4), radius: 8, x: 0, y: 2)
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = max(0, min(value.translation.width, maxDrag))
                    }
                    .onEnded { _ in
                        if maxDrag > 0, dragOffset / maxDrag >= 0.8 {
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                            action()
                        }
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            dragOffset = 0
                        }
                    }
            )
        }
        .frame(height: trackHeight)
    }
}

