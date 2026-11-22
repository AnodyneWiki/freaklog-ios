import SwiftUI

struct CustomSubstanceScreen: View {
  @ObservedObject var customSubstance: CustomSubstance
  @State private var isEditSheetShown = false

  var body: some View {
    // A renamed substance is a different one on AnodyneWiki, so its data is looked up again
    CustomSubstanceList(customSubstance: customSubstance)
      .id(customSubstance.nameUnwrapped)
      .navigationTitle(customSubstance.nameUnwrapped)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Edit") {
            isEditSheetShown = true
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

// The user's own data first, then AnodyneWiki's once it is loaded
private struct CustomSubstanceList: View {
  @ObservedObject var customSubstance: CustomSubstance
  @StateObject private var anodyneModel: AnodyneLoadModel
  // Redraws the screen when the categories change
  @FetchRequest(fetchRequest: PersistenceController.substanceOverridesRequest())
  private var overrides: FetchedResults<SubstanceOverride>

  init(customSubstance: CustomSubstance) {
    self.customSubstance = customSubstance
    _anodyneModel = StateObject(wrappedValue: AnodyneLoadModel(name: customSubstance.nameUnwrapped))
  }

  private var roasWithData: [CustomRoa] {
    customSubstance.customRoasSorted.filter(\.hasData)
  }

  var body: some View {
    let categories = PersistenceController.shared.categories(for: customSubstance.nameUnwrapped)
    List {
      if !customSubstance.explanationUnwrapped.isEmpty || !categories.isEmpty || !customSubstance.unitsUnwrapped.isEmpty {
        overviewSection(categories: categories)
      }
      AnodyneLoadSection(model: anodyneModel)
      if roasWithData.isEmpty {
        Section("Dose & Duration") {
          Text("No dose or duration data added yet. Tap Edit to add data for each route.")
            .foregroundStyle(.secondary)
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
      if let anodyne = anodyneModel.substance {
        AnodyneTopicSections(anodyne: anodyne)
      }
      if anodyneModel.substance != nil || anodyneModel.phase == .notFound {
        SourcesSection(anodyne: anodyneModel.substance, isMissingOnAnodyne: anodyneModel.phase == .notFound)
      }
    }
    .task {
      await anodyneModel.start()
    }
  }

  private func overviewSection(categories: [String]) -> some View {
    Section {
      if !customSubstance.explanationUnwrapped.isEmpty {
        Text(customSubstance.explanationUnwrapped)
      }
      if !categories.isEmpty {
        CategorySection(categoryNames: categories)
      }
      if !customSubstance.unitsUnwrapped.isEmpty {
        LabeledContent("Default Units", value: customSubstance.unitsUnwrapped)
      }
    } header: {
      Text("Overview")
    }
  }
}
