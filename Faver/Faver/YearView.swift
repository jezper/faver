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
                        .font(.system(size: 22, weight: .bold, design: .serif))
                }
                .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                        ForEach(sections) { section in
                            Section {
                                ForEach(section.clusters) { cluster in
                                    Button { selectedCluster = cluster } label: {
                                        ClusterCard(cluster: cluster)
                                    }
                                    .buttonStyle(PressableButtonStyle())
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                                }
                            } header: {
                                Text(section.title.uppercased())
                                    .font(.system(size: 11, weight: .bold, design: .serif))
                                    .foregroundStyle(Color.faver)
                                    .tracking(1.5)
                                    .padding(.horizontal, 16)
                                    .padding(.top, 28)
                                    .padding(.bottom, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.faverBackground)
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
                .background(Color.faverBackground)
            }
        }
        .navigationTitle(String(year))
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.faverBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .fullScreenCover(item: $selectedCluster, onDismiss: {
            photoLibrary.loadAssets()
        }) { cluster in
            ReviewView(photoLibrary: photoLibrary, assets: cluster.assetsToReview)
        }
    }
}
