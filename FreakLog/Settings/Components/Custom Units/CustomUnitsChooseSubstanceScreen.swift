import SwiftUI

struct CustomUnitsChooseSubstanceScreen: View {
    @State private var searchText = ""
    @Environment(\.dismiss) var dismiss

    // Only the most recent ingestions are used to rank substances
    @FetchRequest(fetchRequest: PersistenceController.recentIngestionsRequest(limit: 500))
    private var ingestions: FetchedResults<Ingestion>

    @FetchRequest(fetchRequest: PersistenceController.customSubstancesRequest())
    private var customSubstances: FetchedResults<CustomSubstance>

    private var substancesFilteredAndSorted: [Substance] {
        let substanceNamesInOrder = ingestions.map { ing in
            ing.substanceNameUnwrapped
        }.uniqued()
        return SearchLogic.getFilteredSubstancesSorted(
            substances: SubstanceRepo.shared.substances,
            searchText: searchText,
            namesToSortBy: substanceNamesInOrder
        )
    }

    var customSubstancesFiltered: [CustomSubstance] {
        let lowerCaseSearchText = searchText.lowercased()
        if searchText.count < 3 {
            return customSubstances.filter { cust in
                cust.nameUnwrapped.lowercased().hasPrefix(lowerCaseSearchText)
            }
        } else {
            return customSubstances.filter { cust in
                cust.nameUnwrapped.lowercased().contains(lowerCaseSearchText)
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(substancesFilteredAndSorted) { sub in
                    NavigationLink(value: ChooseRouteScreenArguments(substance: sub)) {
                        SubstanceRowLabel(substance: sub)
                    }
                }
                ForEach(customSubstancesFiltered) { customSubstance in
                    NavigationLink(value: CustomSubstanceChooseRouteScreenArguments(substanceName: customSubstance.nameUnwrapped, units: customSubstance.unitsUnwrapped)) {
                        VStack(alignment: .leading) {
                            Text(customSubstance.nameUnwrapped).font(.headline)
                            Text("custom").font(.subheadline).foregroundColor(.secondary)
                        }
                    }
                }
                if substancesFilteredAndSorted.isEmpty && customSubstancesFiltered.isEmpty {
                    Text("No Results")
                        .foregroundColor(.secondary)
                }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.interactively)
            .searchable(text: $searchText)
            .disableAutocorrection(true)
            .navigationTitle("Choose Substance")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .navigationDestination(for: ChooseRouteScreenArguments.self, destination: { arguments in
                ChooseRouteScreen(substance: arguments.substance, dismiss: dismissSheet)
            })
            .navigationDestination(for: ChooseOtherRouteScreenArguments.self, destination: { arguments in
                ChooseOtherRouteScreen(arguments: arguments, dismiss: dismissSheet)
            })
            .navigationDestination(for: CustomSubstanceChooseRouteScreenArguments.self, destination: { arguments in
                CustomSubstanceChooseRouteScreen(arguments: arguments, dismiss: dismissSheet)
            })
            .navigationDestination(for: CustomUnitArguments.self) { arguments in
                FinishCustomUnitsScreen(arguments: arguments, cancel: dismissSheet, onAdded: { _ in dismissSheet()})
            }
            .navigationDestination(for: SubstanceAndRoute.self) { substanceAndRoute in
                FinishCustomUnitsScreen(arguments: CustomUnitArguments.substance(substance: substanceAndRoute.substance, administrationRoute: substanceAndRoute.administrationRoute), cancel: dismissSheet, onAdded: { _ in dismissSheet()})
            }
            .navigationDestination(for: CustomChooseDoseScreenArguments.self) { arguments in
                FinishCustomUnitsScreen(
                    arguments: CustomUnitArguments.customSubstance(
                        customSubstanceName: arguments.substanceName,
                        administrationRoute: arguments.administrationRoute,
                        customSubstanceUnit: arguments.units
                    ),
                    cancel: dismissSheet,
                    onAdded: { _ in dismissSheet()}
                )
            }
        }
    }

    private func dismissSheet() {
        dismiss()
    }
}

private struct SubstanceRowLabel: View {
    let substance: Substance

    var body: some View {
        VStack(alignment: .leading) {
            Text(substance.name).font(.headline)
            let commonNames = substance.commonNames.joined(separator: ", ")
            if !commonNames.isEmpty {
                Text(commonNames).font(.subheadline).foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    List(SubstanceRepo.shared.substances.prefix(20)) { substance in
        SubstanceRowLabel(substance: substance)
    }.listStyle(.plain)
}
