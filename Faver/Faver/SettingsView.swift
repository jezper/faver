import SwiftUI

struct SettingsView: View {
    @ObservedObject var photoLibrary: PhotoLibraryService
    @AppStorage("clusterMode") private var clusterModeRaw: String = ClusterMode.smart.rawValue
    @AppStorage("clusterGap") private var clusterGapRaw: String = ClusterGap.medium.rawValue
    @AppStorage("smartSensitivity") private var smartSensitivityRaw: String = SmartSensitivity.balanced.rawValue
    @AppStorage("minSetSize") private var minSetSizeRaw: Int = 1
    @Environment(\.dismiss) private var dismiss

    private var clusterMode: ClusterMode {
        ClusterMode(rawValue: clusterModeRaw) ?? .smart
    }
    private var selectedGap: ClusterGap {
        ClusterGap(rawValue: clusterGapRaw) ?? .medium
    }
    private var selectedSensitivity: SmartSensitivity {
        SmartSensitivity(rawValue: smartSensitivityRaw) ?? .balanced
    }
    private var selectedMinSetSize: MinSetSize {
        MinSetSize(rawValue: minSetSizeRaw) ?? .all
    }

    private var filterImpactText: String {
        let total = photoLibrary.clusters.count
        guard total > 0 else { return selectedMinSetSize.description }
        let threshold = selectedMinSetSize.rawValue
        let matching = threshold <= 1
            ? total
            : photoLibrary.clusters.filter { $0.totalInWindow >= threshold }.count
        let hidden = total - matching
        if hidden == 0 {
            return "\(total) sets in your library. \(selectedMinSetSize.description)"
        }
        return "\(matching) of \(total) sets match — \(hidden) smaller \(hidden == 1 ? "set" : "sets") hidden."
    }

    var body: some View {
        NavigationStack {
            Form {
                // Mode + its dependent sub-setting live in one section so the
                // visual grouping makes the parent→child relationship obvious.
                Section {
                    // Primary: mode picker
                    Picker("Mode", selection: $clusterModeRaw) {
                        ForEach(ClusterMode.allCases, id: \.rawValue) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(clusterMode == .smart
                         ? "Automatically detects moments using time gaps and location changes."
                         : "Groups photos by a fixed time window regardless of shooting patterns.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if clusterMode == .smart {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Sensitivity", systemImage: "slider.horizontal.3")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)

                            Picker("Sensitivity", selection: $smartSensitivityRaw) {
                                ForEach(SmartSensitivity.allCases, id: \.rawValue) { s in
                                    Text(s.label).tag(s.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)

                            Text(selectedSensitivity.description)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Time window", systemImage: "clock")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)

                            Picker("Time gap", selection: $clusterGapRaw) {
                                ForEach(ClusterGap.allCases, id: \.rawValue) { gap in
                                    Text(gap.label).tag(gap.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)

                            Text("Groups photos taken within \(selectedGap.description) of each other into one set.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Clustering")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Minimum set size", systemImage: "camera.filters")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)

                        Picker("Minimum set size", selection: $minSetSizeRaw) {
                            ForEach(MinSetSize.allCases, id: \.rawValue) { size in
                                Text(size.label).tag(size.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(filterImpactText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Focus")
                } footer: {
                    Text("Filters sets by total photos in the moment — so a 100-photo vacation with half already reviewed still shows up.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onChange(of: clusterModeRaw) { photoLibrary.loadAssets() }
        .onChange(of: clusterGapRaw) { photoLibrary.loadAssets() }
        .onChange(of: smartSensitivityRaw) { photoLibrary.loadAssets() }
        .onChange(of: minSetSizeRaw) {
            // Filter is applied instantly — no reload needed
            photoLibrary.minSetSizeMinimum = max(1, minSetSizeRaw)
        }
    }
}
