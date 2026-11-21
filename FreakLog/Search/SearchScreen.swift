import SwiftUI
import WrappingHStack
import AppIntents

struct SearchScreen: View {

    @FocusState var isSearchFocused: Bool
    @Binding var searchText: String
    @Binding var selectedCategories: [String]
    let clearCategories: () -> Void


    @State private var isShowingAddCustomSubstance = false


    @FetchRequest(fetchRequest: PersistenceController.customSubstancesRequest())
    private var customSubstances: FetchedResults<CustomSubstance>

    // Redraws the results when the user's categories change
    @FetchRequest(fetchRequest: PersistenceController.substanceOverridesRequest())
    private var overrides: FetchedResults<SubstanceOverride>

    // Only the most recent ingestions are used to rank substances
    @FetchRequest(fetchRequest: PersistenceController.recentIngestionsRequest(limit: 500))
    private var ingestions: FetchedResults<Ingestion>
    
    private static let custom = "custom"
    
    let allCategories = [custom] + SubstanceRepo.shared.categories.map { cat in
        cat.name
    }
    
    func toggleCategory(category: String) {
        if selectedCategories.contains(category) {
            selectedCategories.removeAll { cat in
                cat == category
            }
        } else {
            selectedCategories.append(category)
        }
    }
    
    // "custom" matches every custom substance, other categories those the user gave them
    var customFilteredWithCategories: [CustomSubstance] {
        customSubstances.filter { customSubstance in
            let categories = PersistenceController.shared.categories(for: customSubstance.nameUnwrapped)
            return selectedCategories.allSatisfy { $0 == SearchScreen.custom || categories.contains($0) }
        }
    }
    
    var customSubstancesFiltered: [CustomSubstance] {
        let lowerCaseSearchText = searchText.lowercased()
        if searchText.count < 3 {
            return customFilteredWithCategories.filter { cust in
                cust.nameUnwrapped.lowercased().hasPrefix(lowerCaseSearchText)
            }
        } else {
            return customFilteredWithCategories.filter { cust in
                cust.nameUnwrapped.lowercased().contains(lowerCaseSearchText)
            }
        }
    }
    
    var substancesFilteredAndSorted: [Substance] {
        let substancesFilteredWithCategoriesOnly = SubstanceRepo.shared.substances.filter { sub in
            selectedCategories.allSatisfy { selected in
                PersistenceController.shared.categories(for: sub.name).contains(selected)
            }
        }
        let substanceNamesInOrder = ingestions.map { ing in
            ing.substanceNameUnwrapped
        }.uniqued()
        return SearchLogic.getFilteredSubstancesSorted(
            substances: substancesFilteredWithCategoriesOnly,
            searchText: searchText,
            namesToSortBy: substanceNamesInOrder
        )
    }

    @AppStorage(PersistenceController.isSearchSubstanceSiriTipVisibleKey) private var isSiriTipVisible = false

    var body: some View {
        VStack(spacing: 0) {
            SubstanceSearchBarWithFilter(
                text: $searchText,
                isFocused: $isSearchFocused,
                allCategories: allCategories,
                toggleCategory: { cat in
                    toggleCategory(category: cat)
                },
                selectedCategories: selectedCategories,
                clearCategories: {
                    clearCategories()
                }
            )

            SiriTipView(intent: SearchSubstancesIntent(), isVisible: $isSiriTipVisible)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            List {
                ForEach(substancesFilteredAndSorted) { sub in
                    SearchSubstanceRow(substance: sub)
                }
                ForEach(customSubstancesFiltered) { cust in
                    NavigationLink(value: GlobalNavigationDestination.customSubstance(customSubstance: cust)) {
                        VStack(alignment: .leading) {
                            Text(cust.nameUnwrapped).font(.headline)
                            Spacer().frame(height: 5)
                            WrappingHStack(alignment: .leading, horizontalSpacing: 3, verticalSpacing: 3) {
                                Chip(name: "custom")
                                let categories = PersistenceController.shared.categories(for: cust.nameUnwrapped)
                                ForEach(categories, id: \.self) { category in
                                    Chip(name: category)
                                }
                            }
                        }
                    }
                }
                if substancesFilteredAndSorted.isEmpty && customSubstancesFiltered.isEmpty {
                    Text("No Results")
                        .foregroundColor(.secondary)
                }
                Button {
                    isShowingAddCustomSubstance.toggle()
                } label: {
                    Label("New Custom Substance", systemImage: "plus.circle.fill").labelStyle(.titleAndIcon).font(.headline)
                }
                .sheet(isPresented: $isShowingAddCustomSubstance) {
                    AddCustomSubstanceView(searchText: searchText, onAdded: { _ in})
                }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.interactively)
        }
    }
}
