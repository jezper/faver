import Photos
import SwiftUI

/// Sheet showing every unreviewed moment, grouped by year → month.
/// Tap a row to dismiss the sheet and open that moment in ReviewView.
struct BrowseView: View {
    let library: PhotoLibrary
    let onSelect: (PhotoCluster) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    ForEach(library.yearSections()) { yearSummary in
                        Section {
                            ForEach(library.monthSections(for: yearSummary.year)) { month in
                                monthHeader(month.title)
                                ForEach(month.clusters) { cluster in
                                    ClusterRow(cluster: cluster) {
                                        let c = cluster
                                        dismiss()
                                        Task { @MainActor in
                                            try? await Task.sleep(nanoseconds: 350_000_000)
                                            onSelect(c)
                                        }
                                    }
                                    Divider()
                                        .background(Color.surface2)
                                        .padding(.leading, 84)
                                }
                            }
                        } header: {
                            yearHeader(yearSummary)
                        }
                    }
                }
                .padding(.bottom, 40)
            }
            .background(Color.bg)
            .navigationTitle("All Moments")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Section headers

    private func yearHeader(_ summary: YearSummary) -> some View {
        HStack {
            Text(String(summary.year))
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(.white)
            Spacer()
            Text("\(summary.clusterCount) sets")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.accent)
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background(Color.bg)
    }

    private func monthHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.accent.opacity(0.7))
            .tracking(1.2)
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 4)
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
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(cluster.dateLabel) · \(cluster.count) photos")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .task(id: cluster.id) { thumbnail = await loadThumbnail() }
    }

    private var thumbnailView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.surface)
            if let img = thumbnail {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(width: 56, height: 56)
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
