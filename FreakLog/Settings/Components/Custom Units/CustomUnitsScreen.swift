import CoreData
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
        _fetchRequest = FetchRequest(fetchRequest: PersistenceController.activeCustomUnitsRequest(filter: filter))
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
