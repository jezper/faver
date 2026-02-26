import Photos
import SwiftUI

struct SettingsView: View {
    @ObservedObject var library: PhotoLibrary
    @Environment(\.dismiss) private var dismiss

    @AppStorage("clusterMode")      private var clusterModeRaw: String = ClusterMode.smart.rawValue
    @AppStorage("smartSensitivity") private var sensitivityRaw: String = SmartSensitivity.balanced.rawValue
    @AppStorage("clusterGap")       private var clusterGapRaw:  String = ClusterGap.medium.rawValue
    @AppStorage("minSetSize")       private var minSetSize:      Int    = 1

    private var mode:        ClusterMode      { ClusterMode(rawValue: clusterModeRaw)           ?? .smart    }
    private var sensitivity: SmartSensitivity { SmartSensitivity(rawValue: sensitivityRaw)      ?? .balanced }
    private var gap:         ClusterGap       { ClusterGap(rawValue: clusterGapRaw)             ?? .medium   }

    var body: some View {
        NavigationStack {
            List {
                Section("Set grouping") {
                    Picker("Mode", selection: $clusterModeRaw) {
                        ForEach(ClusterMode.allCases, id: \.rawValue) { m in
                            Text(m.label).tag(m.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    if mode == .smart {
                        Picker("Sensitivity", selection: $sensitivityRaw) {
                            ForEach(SmartSensitivity.allCases, id: \.rawValue) { s in
                                Text(s.label).tag(s.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text(sensitivity.description)
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Picker("Gap", selection: $clusterGapRaw) {
                            ForEach(ClusterGap.allCases, id: \.rawValue) { g in
                                Text(g.label).tag(g.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text(gap.description)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Minimum set size") {
                    Picker("Minimum size", selection: $minSetSize) {
                        ForEach(MinSetSize.allCases, id: \.rawValue) { s in
                            Text(s.label).tag(s.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    let current = MinSetSize(rawValue: minSetSize) ?? .all
                    Text(current.description)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        library.minSize = max(1, minSetSize)
                        library.load()
                        dismiss()
                    }
                    .foregroundStyle(Color.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
