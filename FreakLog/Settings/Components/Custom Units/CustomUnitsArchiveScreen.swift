import CoreData
import SwiftUI

struct CustomUnitsArchiveScreen: View {

    @State private var customUnitToEdit: CustomUnit?

    var body: some View {
        Group {
            if customUnits.isEmpty {
                Text("No archived custom units")
                    .foregroundColor(.secondary)
            } else {
                List {
                    ForEach(customUnits) { customUnit in
                        Button(action: {
                            customUnitToEdit = customUnit
                        }, label: {
                            CustomUnitRow(customUnit: customUnit).foregroundColor(.primary)
                        })
                    }
                }
            }
        }
        .sheet(item: $customUnitToEdit, content: { customUnit in
            NavigationStack {
                EditCustomUnitsScreen(customUnit: customUnit)
            }
        })
        .navigationTitle("Archive")
    }

    @FetchRequest(fetchRequest: PersistenceController.archivedCustomUnitsRequest())
    private var customUnits: FetchedResults<CustomUnit>

}
