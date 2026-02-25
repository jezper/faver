import Photos
import SwiftUI

/// The main review screen — full screen photo display with swipe navigation and favorite toggle.
struct ReviewView: View {
    @ObservedObject var photoLibrary: PhotoLibraryService
    let assets: [PHAsset]

    @Environment(\.dismiss) private var dismiss

    @State private var currentIndex: Int = 0
    @State private var favoritedIDs: Set<String> = []
    /// Indices the user has actually visited — written to ReviewStore only on dismiss.
    @State private var seenIndices: Set<Int> = []

    // Undo toast state
    @State private var undoAsset: PHAsset?
    @State private var undoWasAdding = true
    @State private var undoTimer: Task<Void, Never>?

    var currentAsset: PHAsset? {
        guard !assets.isEmpty, currentIndex < assets.count else { return nil }
        return assets[currentIndex]
    }

    func isFavorited(_ asset: PHAsset) -> Bool {
        favoritedIDs.contains(asset.localIdentifier)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if assets.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.green)
                    Text("Cluster done!")
                        .font(.title)
                        .foregroundStyle(.white)
                    Text("All photos in this set reviewed.")
                        .foregroundStyle(.white.opacity(0.7))
                    Button("Back to library") { dismissAndFlush() }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                }
            } else {
                // Page-swipe TabView. No .clipped() — TabView already clips pages,
                // and .clipped() can interfere with gesture recognition.
                TabView(selection: $currentIndex) {
                    ForEach(assets.indices, id: \.self) { index in
                        AssetImageView(asset: assets[index])
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.black)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
            }
        }
        // Controls are pinned to the edges via overlay(alignment:) rather than
        // a full-screen VStack+Spacer. A VStack with Spacer claims the whole
        // screen for hit-testing and absorbs swipe gestures before they reach
        // the TabView; alignment-anchored overlays only occupy their content area.
        .overlay(alignment: .top) {
            if !assets.isEmpty {
                HStack {
                    Button(action: { dismissAndFlush() }) {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.clear)
                            .glassEffect(in: Circle())
                    }
                    .accessibilityLabel("Close")
                    Spacer()
                    Text("\(currentIndex + 1) / \(assets.count)")
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.clear)
                        .glassEffect(in: Capsule())
                }
                .padding()
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 12) {
                // Undo toast — appears for 3 seconds after any favorite toggle
                if let asset = undoAsset {
                    HStack(spacing: 10) {
                        Image(systemName: undoWasAdding ? "heart.fill" : "heart")
                            .font(.footnote)
                            .foregroundStyle(undoWasAdding ? .red : .white)
                        Text(undoWasAdding ? "Added to favorites" : "Removed from favorites")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                        Spacer()
                        Button("Undo") { performUndo(asset: asset) }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.yellow)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial)
                    .clipShape(Capsule())
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // Heart button
                if let asset = currentAsset {
                    Button(action: { toggleFavorite(asset: asset) }) {
                        Image(systemName: isFavorited(asset) ? "heart.fill" : "heart")
                            .font(.system(size: 28))
                            .foregroundStyle(isFavorited(asset) ? .red : .white)
                            .padding(20)
                            .background(.clear)
                            .glassEffect(in: Circle())
                    }
                    .accessibilityLabel(isFavorited(asset) ? "Remove favorite" : "Add to favorites")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 48)
            .animation(.easeOut(duration: 0.2), value: undoAsset == nil)
        }
        .onAppear {
            seenIndices.insert(0)
        }
        .onChange(of: currentIndex) { _, newIndex in
            if newIndex < assets.count {
                seenIndices.insert(newIndex)
            }
        }
    }

    // MARK: - Private

    /// Marks all visited photos as reviewed, then dismisses.
    private func dismissAndFlush() {
        undoTimer?.cancel()
        for index in seenIndices where index < assets.count {
            photoLibrary.markReviewed(assets[index])
        }
        dismiss()
    }

    private func toggleFavorite(asset: PHAsset) {
        let adding = !isFavorited(asset)
        if adding {
            favoritedIDs.insert(asset.localIdentifier)
        } else {
            favoritedIDs.remove(asset.localIdentifier)
        }
        photoLibrary.toggleFavorite(asset: asset, newValue: adding)

        // Reset the 3-second undo window
        undoTimer?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            undoAsset = asset
            undoWasAdding = adding
        }
        undoTimer = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { undoAsset = nil }
        }
    }

    private func performUndo(asset: PHAsset) {
        undoTimer?.cancel()
        undoTimer = nil
        let currentlyFav = isFavorited(asset)
        if currentlyFav {
            favoritedIDs.remove(asset.localIdentifier)
        } else {
            favoritedIDs.insert(asset.localIdentifier)
        }
        photoLibrary.toggleFavorite(asset: asset, newValue: !currentlyFav)
        withAnimation(.easeOut(duration: 0.2)) { undoAsset = nil }
    }
}
