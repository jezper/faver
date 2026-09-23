import Photos
import SwiftUI

/// Sheet showing every unreviewed moment, grouped by year → month.
/// Tap a row to dismiss the sheet and open that moment in ReviewView.
struct BrowseView: View {
    let library: LibraryService
    let onSelect: (PhotoCluster) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    // One Section per month — direct children of LazyVStack so their
                    // headers are pinned. Year is embedded in the header, not a separate
                    // outer section, which is why month pinning now works correctly.
                    ForEach(library.yearSections()) { yearSummary in
                        ForEach(library.monthSections(for: yearSummary.year)) { month in
                            Section {
                                rows(for: month)
                            } header: {
                                monthHeader(month.title, year: yearSummary.year)
                            }
                        }
                    }
                }
                .padding(.bottom, 40)
            }
            .background(Color.bg)
            .navigationTitle("All Moments")
            .navigationBarTitleDisplayMode(.large)
            // No toolbarBackground override. A flat fill was being painted over the
            // system's glass bar, which is the one surface that resolves scrolling
            // thumbnails behind a title well.
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Rows

    /// Kept out of the body on purpose. Inlined inside the nested ForEach/Section the
    /// type-checker gives up on the whole expression.
    private func rows(for month: MonthSection) -> some View {
        ForEach(month.clusters) { cluster in
            ClusterRow(cluster: cluster) { select(cluster) }
            Divider()
                .background(Color.surface2)
                .padding(.leading, 84)
        }
    }

    private func select(_ cluster: PhotoCluster) {
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            onSelect(cluster)
        }
    }

    // MARK: - Section header

    /// Combined sticky header: year (small, subdued) above month (bold, all-caps).
    /// Shown for every month section — keeps both year and month visible at all times.
    private func monthHeader(_ title: String, year: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(String(year))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.accent.opacity(0.7))
                .tracking(1.2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bg)
    }
}

// MARK: - Cluster row

private struct ClusterRow: View {
    let cluster: PhotoCluster
    let action: () -> Void

    @State private var thumbnail: UIImage? = nil

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                thumbnailView
                VStack(alignment: .leading, spacing: 3) {
                    Text(cluster.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(cluster.dateLabel) · \(cluster.count) photos")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.35))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(cluster.title), \(cluster.dateLabel), \(cluster.count) photos left to review")
        .accessibilityHint("Opens this moment")
        .task(id: cluster.id) { thumbnail = await loadThumbnail() }
    }

    private var thumbnailView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.surface)
            if let img = thumbnail {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(width: 56, height: 56)
        .clipped()
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
                targetSize: CGSize(width: 112, height: 112),
                contentMode: .aspectFill,
                options: opts
            ) { img, _ in continuation.resume(returning: img) }
        }
    }
}
