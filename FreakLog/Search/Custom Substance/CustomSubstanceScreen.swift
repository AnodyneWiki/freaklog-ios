import SwiftUI

struct CustomSubstanceScreen: View {
  @ObservedObject var customSubstance: CustomSubstance
  @State private var isEditSheetShown = false

  private var roasWithData: [CustomRoa] {
    customSubstance.customRoasSorted.filter(\.hasData)
  }

  var body: some View {
    List {
      if !customSubstance.explanationUnwrapped.isEmpty {
        Section("About") {
          Text(customSubstance.explanationUnwrapped)
        }
      }
      if !customSubstance.unitsUnwrapped.isEmpty {
        Section("Default Units") {
          Text(customSubstance.unitsUnwrapped)
            .foregroundStyle(.secondary)
        }
      }
      if roasWithData.isEmpty {
        Section {
          Text("No dose or duration data added yet. Tap the edit button to add data for each route.")
            .foregroundStyle(.secondary)
            .font(.subheadline)
        } header: {
          Text("Data")
        }
      } else {
        ForEach(roasWithData, id: \.objectID) { roa in
          Section(roa.administrationRouteUnwrapped.rawValue.localizedCapitalized) {
            RoaPreview(
              substanceName: customSubstance.nameUnwrapped,
              route: roa.administrationRouteUnwrapped,
              roaDose: roa.roaDose,
              roaDuration: roa.roaDuration
            )
          }
        }
      }
    }
    .navigationTitle(customSubstance.nameUnwrapped)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          isEditSheetShown = true
        } label: {
          Label("Edit", systemImage: "pencil")
        }
      }
    }
    .sheet(isPresented: $isEditSheetShown) {
      NavigationStack {
        EditCustomSubstanceView(customSubstance: customSubstance)
      }
    }
  }
}
