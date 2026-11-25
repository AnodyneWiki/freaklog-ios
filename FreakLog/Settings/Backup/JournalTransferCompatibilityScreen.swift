import CoreData
import SwiftUI

struct JournalTransferCompatibilityScreen: View {
    let viewModel: SettingsScreen.ViewModel

    private enum Destination: String, CaseIterable, Identifiable {
        case android = "FreakLog Android"
        case pwJournal = "PW Journal 18.0"
        case psyLog = "PsyLog"

        var id: String { rawValue }

        var fileDescription: String {
            switch self {
            case .android:
                "Journal JSON uses the FreakLog Android journal structure. Check the transferred records after import."
            case .pwJournal:
                "PW Journal 18.0 stores locations on experiences. Confirming an export option requires a test import in PW Journal."
            case .psyLog:
                "Confirming an export option requires a test import with the destination version of PsyLog."
            }
        }
    }

    @FetchRequest(fetchRequest: PersistenceController.ingestionsRequest())
    private var ingestions: FetchedResults<Ingestion>
    @FetchRequest(fetchRequest: PersistenceController.formulationsRequest())
    private var formulations: FetchedResults<Formulation>
    @State private var destination = Destination.android

    var body: some View {
        List {
            Section {
                Picker("Destination", selection: $destination) {
                    ForEach(Destination.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
            } footer: {
                Text(destination.fileDescription)
            }

            if destination != .psyLog {
                Section {
                    LabeledContent("Locations on Individual Ingestions", value: individualLocations.formatted())
                    LabeledContent("Formulations", value: formulations.count.formatted())
                } header: {
                    Text("Review Before Transfer")
                } footer: {
                    Text("Individual ingestion locations may be omitted. Saved formulation definitions and their links may be lost even when the underlying ingestions transfer.")
                }
            }

            if destination == .android {
                Section {
                    NavigationLink {
                        JournalExportReview(viewModel: viewModel, isBackup: false)
                    } label: {
                        Label("Review Journal JSON", systemImage: "doc.text")
                    }
                } footer: {
                    Text("Use FreakLog Backup if you want to restore the full journal in FreakLog for iOS.")
                }
            }
        }
        .navigationTitle("Transfer Compatibility")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var individualLocations: Int {
        ingestions.lazy.filter { $0.location != nil }.count
    }
}
