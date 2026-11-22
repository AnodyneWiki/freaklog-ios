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

  // Routes with the user's data or AnodyneWiki timings, which fill in durations the user didn't enter
  private var routes: [AdministrationRoute] {
    let name = customSubstance.nameUnwrapped
    let customRoutes = Set(customSubstance.customRoasSorted.filter(\.hasData).map(\.administrationRouteUnwrapped))
    let anodyneRoutes = Set(AnodyneTimingStore.shared.routesWithTimings(for: name))
    return AdministrationRoute.allCases.filter { customRoutes.contains($0) || anodyneRoutes.contains($0) }
  }

  var body: some View {
    let categories = PersistenceController.shared.categories(for: customSubstance.nameUnwrapped)
    List {
      if !customSubstance.explanationUnwrapped.isEmpty || !categories.isEmpty || !customSubstance.unitsUnwrapped.isEmpty
        || anodyneModel.substance != nil {
        overviewSection(categories: categories)
      }
      AnodyneLoadSection(model: anodyneModel)
      if routes.isEmpty {
        Section("Dose & Duration") {
          Text("No dose or duration data added yet. Tap Edit to add data for each route.")
            .foregroundStyle(.secondary)
        }
      } else {
        let name = customSubstance.nameUnwrapped
        ForEach(routes, id: \.self) { route in
          Section {
            RoaPreview(
              substanceName: name,
              route: route,
              roaDose: PersistenceController.shared.resolvedDose(for: name, route: route),
              roaDuration: PersistenceController.shared.resolvedDuration(for: name, route: route)
            )
          } header: {
            Text(route.rawValue.localizedCapitalized)
          } footer: {
            if PersistenceController.shared.isDurationFromAnodyneWiki(for: name, route: route) {
              Text(AnodyneDurationSection.timingFootnote)
            }
          }
        }
      }
      if let anodyne = anodyneModel.substance {
        // The routes above already show AnodyneWiki's timings
        AnodyneTopicSections(anodyne: anodyne, userNotes: anodyneModel.userNotes, isShowingRouteTimings: false)
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
      if let anodyne = anodyneModel.substance {
        AnodyneChemistryRows(anodyne: anodyne, substanceName: customSubstance.nameUnwrapped)
      }
    } header: {
      Text("Overview")
    }
  }
}
