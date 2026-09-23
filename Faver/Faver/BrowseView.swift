import Photos
import SwiftUI

/// Sheet showing moments grouped by year → month, in two lists: the queue, and the
/// archive of moments already been through.
///
/// The archive exists because a finished moment used to vanish completely, and the only
/// way back was resetting every moment ever reviewed. Nobody would want that. Being able
/// to walk back into one moment and change your mind is the useful version.
struct BrowseView: View {
    let library: LibraryService
    let onSelect: (PhotoCluster, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingArchive = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if !library.archive.isEmpty {
                    Picker("", selection: $showingArchive) {
                        Text("To review").tag(false)
                        Text("Reviewed").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("browse-scope")
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                }

                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    // One Section per month — direct children of LazyVStack so their
                    // headers are pinned. Year is embedded in the header, not a separate
                    // outer section, which is why month pinning now works correctly.
                    ForEach(library.yearSections(archived: showingArchive)) { yearSummary in
                        ForEach(library.monthSections(for: yearSummary.year, archived: showingArchive)) { month in
                            Section {
                                rows(for: month)
                            } header: {
                                monthHeader(month.title, year: yearSummary.year)
                            }
                        }
                    }
                }
                if showingArchive && library.archive.isEmpty {
                    emptyArchive
                }
            }
            .padding(.bottom, 40)
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
            ClusterRow(cluster: cluster, archived: showingArchive) { select(cluster) }
            Divider()
                .background(Color.surface2)
                .padding(.leading, 84)
        }
    }

    /// Hands the choice up and closes. The parent opens it once this sheet is gone.
    private func select(_ cluster: PhotoCluster) {
        onSelect(cluster, showingArchive)
        dismiss()
    }

    private var emptyArchive: some View {
        VStack(spacing: 10) {
            Text("Nothing here yet.")
                .font(.system(.title3, design: .serif).weight(.bold))
                .foregroundStyle(.white)
            Text("Moments you finish show up here,\nso you can always go back in.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
        .frame(maxWidth: .infinity)
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
    var archived: Bool = false
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
                    Text("\(cluster.dateLabel) · \(countLabel)")
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
        .accessibilityLabel("\(cluster.title), \(cluster.dateLabel), \(countLabel)")
        .accessibilityHint(archived ? "Opens this moment again" : "Opens this moment")
        .accessibilityIdentifier("moment-row")
        .task(id: cluster.id) { thumbnail = await loadThumbnail() }
    }

    private var countLabel: String {
        let n = archived ? cluster.allAssets.count : cluster.count
        return archived ? "\(n) photos" : "\(n) photo\(n == 1 ? "" : "s") left"
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
        guard let asset = (archived ? cluster.allAssets : cluster.assetsToReview).first else { return nil }
        return await ThumbnailCache.shared.image(
            for: asset,
            size: ThumbnailCache.rowSize,
            allowsNetwork: false,
            exact: true
        )
    }
}
