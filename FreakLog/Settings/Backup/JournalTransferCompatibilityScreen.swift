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
                NavigationLink {
                    JournalExportReview(viewModel: viewModel, isBackup: false, pwJournalVersion: .current)
                } label: {
                    Label("Review Journal 18.0 Transfer", systemImage: "doc.text")
                }
            }
            Section {
                NavigationLink {
                    JournalExportReview(viewModel: viewModel, isBackup: false, pwJournalVersion: .legacy)
                } label: {
                    Label("Review Journal 11.11 Transfer", systemImage: "doc.text")
                }
            } header: {
                Text("PW Journal 11.11")
            } footer: {
                Text("Use the legacy file with Journal 11.11. For recent versions of Journal, choose the 18.0 transfer.")
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
