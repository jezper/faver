import Photos
import SwiftUI

/// Full-screen, immersive photo review for a single moment.
/// Horizontal swipe through all photos; one amber button picks the best.
struct ReviewView: View {
    let library: PhotoLibrary
    let cluster: PhotoCluster

    @Environment(\.dismiss) private var dismiss
    @State private var currentPage: Int = 0
    @State private var showToast = false
    @State private var isPicking = false

    private let haptics = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Photo pager
            TabView(selection: $currentPage) {
                ForEach(Array(cluster.assetsToReview.enumerated()), id: \.element.localIdentifier) { i, asset in
                    ZoomableImageView(asset: asset)
                        .tag(i)
                        .ignoresSafeArea()
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            // HUD — top + bottom
            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomBar
            }
            .ignoresSafeArea(edges: .bottom)

            // Toast
            if showToast {
                VStack {
                    Spacer()
                    toastView.padding(.bottom, 120)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .statusBarHidden()
        .animation(.easeInOut(duration: 0.35), value: showToast)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button { skip() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Skip this moment")

            Spacer()

            let total = cluster.assetsToReview.count
            Text("\(currentPage + 1) / \(total)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 12) {
            Button { pick() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill")
                    Text("This is the one")
                }
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(isPicking ? Color.accent.opacity(0.6) : Color.accent,
                            in: RoundedRectangle(cornerRadius: 17))
            }
            .buttonStyle(PressScaleStyle())
            .disabled(isPicking)
            .padding(.horizontal, 20)
            .accessibilityLabel("Favorite this photo and finish reviewing")

            Button { skip() } label: {
                Text("Skip this moment")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.bottom, 36)
        }
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

    // MARK: - Toast

    private var toastView: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.accent)
            Text("Moment curated")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 13)
        .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: - Actions

    private func pick() {
        guard !isPicking else { return }
        isPicking = true
        haptics.impactOccurred()

        let asset = cluster.assetsToReview[safe: currentPage] ?? cluster.assetsToReview[0]
        library.favorite(asset, on: true)
        cluster.assetsToReview.forEach { library.markSeen($0) }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showToast = true }

        Task {
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            dismiss()
        }
    }

    private func skip() {
        cluster.assetsToReview.forEach { library.markSeen($0) }
        dismiss()
    }
}
