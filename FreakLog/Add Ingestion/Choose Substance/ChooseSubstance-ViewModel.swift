@preconcurrency import CoreData //FIXME
import Foundation

// swiftlint:disable function_body_length
extension ChooseSubstanceScreen {
    @MainActor
    class ViewModel: NSObject, ObservableObject, NSFetchedResultsControllerDelegate {
        @Published var searchText = ""
        @Published var isShowingOpenEyeToast = false
        @Published var filteredSuggestions: [any SuggestionProtocol] = []
        @Published var filteredSubstances: [Substance] = []
        @Published var filteredCustomUnits: [CustomUnit] = []
        @Published var filteredCustomSubstances: [CustomSubstanceModel] = []
        @Published var customSubstanceModels: [CustomSubstanceModel]
        @Published var isEyeOpen = false

        private let allPossibleSuggestions: [any SuggestionProtocol]
        private let fetchController: NSFetchedResultsController<CustomSubstance>?

        private static func getSortedIngestions() -> [Ingestion] {
            PersistenceController.shared.getRecentIngestions(limit: 1000)
        }

        private static func getCustomUnits() -> [CustomUnit] {
            PersistenceController.shared.getActiveCustomUnits()
        }

        override init() {
            isEyeOpen = UserDefaults.standard.bool(forKey: PersistenceController.isEyeOpenKey2)
            let customUnits = Self.getCustomUnits()
            allPossibleSuggestions = getSuggestions(sortedIngestions: Self.getSortedIngestions(), customUnits: customUnits)
            fetchController = NSFetchedResultsController(
                fetchRequest: PersistenceController.customSubstancesRequest(),
                managedObjectContext: PersistenceController.shared.viewContext,
                sectionNameKeyPath: nil,
                cacheName: nil
            )
            try? fetchController?.performFetch()
            let customSubstances = fetchController?.fetchedObjects ?? []
            customSubstanceModels = customSubstances.map { cust in
                CustomSubstanceModel(
                    name: cust.nameUnwrapped,
                    description: cust.explanationUnwrapped,
                    units: cust.unitsUnwrapped
                )
            }
            super.init()
            fetchController?.delegate = self
            $searchText
                .combineLatest($isEyeOpen) { search, isEyeOpen in
                    let allSubstances = SubstanceRepo.shared.substances
                    let originalFiltered = SearchLogic.getFilteredSubstancesSorted(substances: allSubstances, searchText: search, namesToSortBy: [])
                    if isEyeOpen {
                        return originalFiltered
                    } else {
                        let isContainingIllegal = originalFiltered.contains { sub in
                            !namesOfLegalSubstances.contains(sub.name)
                        }
                        if search.count > 4 && isContainingIllegal {
                            self.openEyeAndAnimate()
                            return originalFiltered
                        } else {
                            return originalFiltered.filter { sub in
                                namesOfLegalSubstances.contains(sub.name)
                            }
                        }
                    }
                }.assign(to: &$filteredSubstances)
            $searchText
                .combineLatest($customSubstanceModels) { search, customs in
                    if search.isEmpty {
                        return customs
                    } else {
                        let searchLowerCased = search.lowercased()
                        return customs.filter { custModel in
                            custModel.name.lowercased().contains(searchLowerCased)
                        }
                    }
                }.assign(to: &$filteredCustomSubstances)
            $filteredSubstances.combineLatest($filteredCustomSubstances, $searchText) { [self] filteredSubstances, filteredCustom, searchTextValue in
                let substanceNames = filteredSubstances.map(\.name) + filteredCustom.map(\.name)
                return allPossibleSuggestions.filter { suggestion in
                    suggestion.isInResult(searchText: searchTextValue, substanceNames: substanceNames)
                }
            }.assign(to: &$filteredSuggestions)
            $searchText.combineLatest($filteredSubstances) { searchText, filteredSubstances in
                let substanceNames = Set(filteredSubstances.map(\.name))
                let search = searchText.lowercased()
                return customUnits.filter { customUnit in
                    substanceNames.contains(customUnit.substanceNameUnwrapped)
                    || customUnit.nameUnwrapped.lowercased().contains(search)
                    || customUnit.substanceNameUnwrapped.lowercased().contains(search)
                    || customUnit.unitUnwrapped.lowercased().contains(search)
                    || customUnit.noteUnwrapped.lowercased().contains(search)
                }
            }.assign(to: &$filteredCustomUnits)
        }

        private func openEyeAndAnimate() {
            isEyeOpen = true
            UserDefaults.standard.set(true, forKey: PersistenceController.isEyeOpenKey2)
            isShowingOpenEyeToast = true
        }

        public nonisolated func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
            Task { @MainActor in
                guard let custs = controller.fetchedObjects as? [CustomSubstance] else { return }
                self.customSubstanceModels = custs.map { cust in
                    CustomSubstanceModel(
                        name: cust.nameUnwrapped,
                        description: cust.explanationUnwrapped,
                        units: cust.unitsUnwrapped
                    )
                }
            }
        }
    }
}
// swiftlint:enable function_body_length
