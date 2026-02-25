import Photos
import SwiftUI

/// Clusters for a single year, grouped by month with cards.
struct YearView: View {
    let year: Int
    @ObservedObject var photoLibrary: PhotoLibraryService
    @State private var selectedCluster: PhotoCluster?

    var sections: [MonthSection] { photoLibrary.monthSections(for: year) }

    var body: some View {
        Group {
            if sections.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.faver)
                    Text("All done for \(String(year))!")
                        .font(.title2)
                }
                .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                        ForEach(sections) { section in
                            Section {
                                ForEach(section.clusters) { cluster in
                                    ClusterCard(cluster: cluster)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 6)
                                        .onTapGesture { selectedCluster = cluster }
                                }
                            } header: {
                                Text(section.title)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .glassEffect(in: Capsule())
                                    .padding(.leading, 16)
                                    .padding(.top, 20)
                                    .padding(.bottom, 10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .navigationTitle(String(year))
        .navigationBarTitleDisplayMode(.large)
        .fullScreenCover(item: $selectedCluster, onDismiss: {
            photoLibrary.loadAssets()
        }) { cluster in
            ReviewView(photoLibrary: photoLibrary, assets: cluster.assetsToReview)
        }
    }
}
