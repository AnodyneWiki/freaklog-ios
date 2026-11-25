import CoreData
import SwiftUI

struct AddCustomSubstanceView: View {

    let searchText: String
    let onAdded: (ChooseRouteScreenArguments) -> Void

    @StateObject private var viewModel = ViewModel()
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PersistenceController.isEyeOpenKey2) var isEyeOpen: Bool = false
    @FetchRequest(fetchRequest: PersistenceController.customSubstancesRequest())
    private var customSubstances: FetchedResults<CustomSubstance>
    @State private var saveError: String?

    private var nameIsTaken: Bool {
        customSubstances.contains { SimilarSubstanceNames.isSameName($0.nameUnwrapped, viewModel.trimmedName) }
            || SubstanceRepo.shared.substances.contains { SimilarSubstanceNames.isSameName($0.name, viewModel.trimmedName) }
    }

    private var suggestedSubstances: [AddIngestionSubstance] {
        let name = viewModel.trimmedName
        guard !name.isEmpty else { return [] }
        var matches: [(AddIngestionSubstance, Int)] = customSubstances.compactMap { custom in
            SimilarSubstanceNames.distance(name, custom.nameUnwrapped).map {
                (.custom(name: custom.nameUnwrapped, units: custom.unitsUnwrapped), $0)
            }
        }
        for substance in SubstanceRepo.shared.substances {
            if let distance = SimilarSubstanceNames.distance(name, substance.name) {
                matches.append((.psychonautWiki(substance), distance))
            } else if substance.commonNames.contains(where: { SimilarSubstanceNames.isSameName($0, name) }) {
                matches.append((.psychonautWiki(substance), 0))
            }
        }
        return Array(matches.sorted { first, second in
            if first.1 != second.1 { return first.1 < second.1 }
            return first.0.name.localizedStandardCompare(second.0.name) == .orderedAscending
        }.map(\.0).uniqued().prefix(5))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField(
                        "Name",
                        text: $viewModel.name,
                        prompt: Text("Enter Name")
                    )
                    .disableAutocorrection(true)
                }
                let suggestions = suggestedSubstances
                if !suggestions.isEmpty {
                    Section {
                        ForEach(suggestions, id: \.self) { substance in
                            Button {
                                open(substance)
                            } label: {
                                LabeledContent(substance.displayName, value: "Use Existing")
                            }
                        }
                    } header: {
                        Text("Similar Substances")
                    } footer: {
                        if nameIsTaken {
                            Text("Choose the existing substance or enter a different name.")
                        }
                    }
                }
                Section("Description") {
                    TextField(
                        "Description",
                        text: $viewModel.explanation,
                        prompt: Text("Enter Description")
                    )
                    .disableAutocorrection(true)
                }
                Section("Units") {
                    UnitsPicker(units: $viewModel.units)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.name) { newValue in
                if !isEyeOpen {
                    let allSubstances = SubstanceRepo.shared.substances
                    let originalFiltered = SearchLogic.getFilteredSubstancesSorted(substances: allSubstances, searchText: newValue, namesToSortBy: [])
                    if newValue.count > 3 && originalFiltered.count > 0 {
                        isEyeOpen = true
                    }
                }
            }
            .onAppear(perform: {
                viewModel.name = searchText
            })
            .navigationTitle("Create Custom")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if viewModel.isEverythingNeededDefined && !nameIsTaken {
                        DoneButton {
                            do {
                                open(try viewModel.saveCustom())
                            } catch {
                                saveError = error.localizedDescription
                            }
                        }
                    }
                }
            }
            .alert("Couldn’t save substance", isPresented: Binding(
                get: { saveError != nil }, set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private func open(_ substance: AddIngestionSubstance) {
        onAdded(ChooseRouteScreenArguments(substance: substance))
        dismiss()
    }
}

#Preview {
    AddCustomSubstanceView(searchText: "My subs", onAdded: {_ in })
}
