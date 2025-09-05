import SwiftUI

// MARK: - CustomUnitsScreen

struct CustomUnitsScreen: View {

    @State private var searchText: String = ""
    @State private var isAddShown = false

    var body: some View {
        FilteredCustomUnits(filter: searchText)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink(value: GlobalNavigationDestination.customUnitsArchive) {
                        Label("Archive", systemImage: "archivebox")
                    }
                    Button {
                        isAddShown.toggle()
                    } label: {
                        Label("Add Custom Unit", systemImage: "plus").labelStyle(.iconOnly)
                    }
                }
            }
            .fullScreenCover(isPresented: $isAddShown, content: {
                CustomUnitsChooseSubstanceScreen()
            })
            .navigationTitle("Custom Units")
    }
}

struct FilteredCustomUnits: View {

    @FetchRequest var fetchRequest: FetchedResults<CustomUnit>
    @State private var customUnitToEdit: CustomUnit?

    init(filter: String) {
        let isArchivedPredicate = NSPredicate(
            format: "isArchived == %@",
            NSNumber(value: false))
        let namePredicate = NSPredicate(format: "name CONTAINS[c] %@", filter)
        let substancePredicate = NSPredicate(format: "substanceName CONTAINS[c] %@", filter)
        let unitPredicate = NSPredicate(format: "unit CONTAINS[c] %@", filter)
        let notePredicate = NSPredicate(format: "note CONTAINS[c] %@", filter)
        let administrationRoutePredicate = NSPredicate(format: "administrationRoute CONTAINS[c] %@", filter)
        let searchTextPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [namePredicate, substancePredicate, unitPredicate, notePredicate, administrationRoutePredicate])
        let compoundPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [isArchivedPredicate, searchTextPredicate])
        let finalPredicate = filter.isEmpty ? isArchivedPredicate : compoundPredicate
        _fetchRequest = FetchRequest<CustomUnit>(
            sortDescriptors: [NSSortDescriptor(keyPath: \CustomUnit.creationDate, ascending: false)],
            predicate: finalPredicate)
    }

    var body: some View {
        List {
            if fetchRequest.isEmpty {
                Text("No custom units")
                    .foregroundColor(.secondary)
            }

            ForEach(fetchRequest) { customUnit in
                Button(action: {
                    customUnitToEdit = customUnit
                }, label: {
                    CustomUnitRow(customUnit: customUnit).foregroundColor(.primary)
                })
            }
        }
        .listStyle(.plain)
        .sheet(item: $customUnitToEdit, content: { customUnit in
            NavigationStack {
                EditCustomUnitsScreen(customUnit: customUnit)
            }
        })
    }
}
