import Photos
import SwiftUI

/// Three questions, each of which changes something the user can actually see.
///
/// There used to be four, and two of them asked the same thing twice: a Smart/Fixed mode
/// switch, where Fixed replaced the smart grouping with a single blunt time threshold and
/// then needed its own three-way control to set it. Smart already has a time tier, plus
/// day boundaries and venue changes that Fixed could not see at all, so Fixed was a worse
/// answer to a question that was already answered. It is gone, along with having to
/// understand the difference before touching anything.
struct SettingsView: View {
    @ObservedObject var library: LibraryService
    @Environment(\.dismiss) private var dismiss

    @AppStorage("smartSensitivity")   private var sensitivityRaw: String = SmartSensitivity.balanced.rawValue
    @AppStorage("minSetSize")         private var minSetSize: Int = 1
    @AppStorage("includeScreenshots") private var includeScreenshots: Bool = false

    private var sensitivity: SmartSensitivity { SmartSensitivity(rawValue: sensitivityRaw) ?? .balanced }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("How moments are grouped", selection: $sensitivityRaw) {
                        ForEach(SmartSensitivity.allCases, id: \.rawValue) { s in
                            Text(s.label).tag(s.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(sensitivity.description)
                        .font(.caption).foregroundStyle(.secondary)
                } header: {
                    Text("How moments are grouped")
                } footer: {
                    // Worth saying out loud: moments are worked out from these settings
                    // rather than stored, so changing one redraws all of them. The thing
                    // people would actually worry about losing is safe, and saying so is
                    // cheaper than letting them find out.
                    Text("Changing this regroups every moment. What you have already reviewed stays reviewed — that is remembered per photo, not per moment.")
                }

                if library.hasLimitedAccess {
                    Section {
                        Button("Choose photos") { library.presentLimitedPicker() }
                    } header: {
                        Text("Photo access")
                    } footer: {
                        Text("Faver can only see the photos you picked. Everything else in your library stays invisible to it.")
                    }
                }

                Section {
                    Toggle("Screenshots", isOn: $includeScreenshots)
                } header: {
                    Text("What to include")
                } footer: {
                    Text(includeScreenshots
                         ? "Screenshots appear alongside your photos."
                         : "Screenshots stay out of the way. Nothing is deleted — they are simply not asked about.")
                }

                Section {
                    Picker("What to show", selection: $minSetSize) {
                        ForEach(MinSetSize.allCases, id: \.rawValue) { s in
                            Text(s.label).tag(s.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text((MinSetSize(rawValue: minSetSize) ?? .all).description)
                        .font(.caption).foregroundStyle(.secondary)
                } header: {
                    Text("What to show")
                } footer: {
                    // Named for what it does rather than for how it works. "Minimum set
                    // size" describes the implementation; a person wants to say "just the
                    // big trips for now". Smaller moments are hidden, never spent.
                    Text("Smaller moments are set aside, not finished. They come back whenever you widen this.")
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
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
