import CoreData
import SwiftUI

struct JournalTransferCompatibilityScreen: View {
    let viewModel: SettingsScreen.ViewModel

    @FetchRequest(fetchRequest: PersistenceController.ingestionsRequest())
    private var ingestions: FetchedResults<Ingestion>
    @FetchRequest(fetchRequest: PersistenceController.formulationsRequest())
    private var formulations: FetchedResults<Formulation>

    var body: some View {
        List {
            Section("FreakLog Android 11.36") {
                NavigationLink {
                    JournalExportReview(viewModel: viewModel, isBackup: false, isAndroidTransfer: true)
                } label: {
                    Label("Review Android Transfer", systemImage: "doc.text")
                }
                if individualLocations > 0 {
                    LabeledContent("Locations on Individual Ingestions", value: individualLocations.formatted())
                }
                if !formulations.isEmpty {
                    LabeledContent("Formulations", value: formulations.count.formatted())
                }
            }
            Section("PW Journal 18.0") {
                Text("Restore Journal accepts supported PW Journal 18 exports. Journal uses experience locations. Export to PW Journal requires verification with the destination app.")
            }
            Section("PsyLog") {
                Text("Export to PsyLog requires verification with the destination app.")
            }
        }
        .navigationTitle("Transfer Compatibility")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var individualLocations: Int {
        ingestions.lazy.filter { $0.location != nil }.count
    }
}
