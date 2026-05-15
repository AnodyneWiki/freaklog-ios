import SwiftUI

struct WatchSettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
                Section("About") {
                    LabeledContent("App", value: "FreakLog Watch")
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
                }
                Section("Sync") {
                    Label("CloudKit Active", systemImage: "icloud.fill")
                        .foregroundStyle(.green)
                    Text("Experiences and ingestions sync automatically with your iPhone via iCloud.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Safety") {
                    NavigationLink {
                        SaferUseTipsView()
                    } label: {
                        Label("Harm Reduction", systemImage: "heart.fill")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

struct SaferUseTipsView: View {
    let tips: [String] = [
        "Start with a low dose, especially with new substances.",
        "Test your substances when possible.",
        "Avoid mixing depressants (alcohol, benzos, opioids).",
        "Have a sober trip-sitter for psychedelics.",
        "Stay hydrated, but don't overdo it.",
        "Allow time between sessions to reset tolerance.",
        "Know what you are taking - check interactions on iPhone."
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(tips, id: \.self) { tip in
                    HStack(alignment: .top) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(tip)
                            .font(.footnote)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Safer Use")
        .navigationBarTitleDisplayMode(.inline)
    }
}
