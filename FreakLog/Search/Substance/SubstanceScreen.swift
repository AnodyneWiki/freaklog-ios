import SwiftUI

struct SubstanceScreen: View {
  let substance: Substance

  @State private var isShowingCustomizeSheet = false
  @StateObject private var anodyneModel: AnodyneLoadModel
  @FetchRequest private var customRoas: FetchedResults<CustomRoa>
  // Redraws the screen when the user's name or categories for the substance change
  @FetchRequest private var overrides: FetchedResults<SubstanceOverride>

  init(substance: Substance) {
    self.substance = substance
    _anodyneModel = StateObject(wrappedValue: AnodyneLoadModel(name: substance.name, otherNames: substance.commonNames))
    _customRoas = FetchRequest(fetchRequest: PersistenceController.customRoasRequest(for: substance.name))
    _overrides = FetchRequest(fetchRequest: PersistenceController.substanceOverridesRequest(for: substance.name))
  }

  // Each topic shows PsychonautWiki's information, completed with AnodyneWiki's once it is loaded
  var body: some View {
    let anodyne = anodyneModel.substance
    List {
      overviewSection(anodyne: anodyne)
      AnodyneLoadSection(model: anodyneModel)
      EffectsSection(summary: substance.effectsSummary, anodyne: anodyne)
      if let anodyne {
        AnodyneReportsSection(anodyne: anodyne, userNotes: anodyneModel.userNotes)
      }
      Group {
        let hasDoses = substance.dosageRemark != nil || !substance.doseInfos.isEmpty
          || customRoas.contains(where: { $0.roaDose != nil }) || anodyne?.dosing.isEmpty == false
        if hasDoses {
          DosesSection(substance: substance, anodyne: anodyne)
        }
        if !substance.durationInfos.isEmpty || customRoas.contains(where: { $0.roaDuration != nil })
          || (anodyne != nil && hasAnodyneTimings) {
          DurationSection(substance: substance, anodyne: anodyne)
        } else if let anodyne {
          AnodyneDurationSection(anodyne: anodyne)
        }
        InteractionsSection(substance: substance, anodyne: anodyne)
        if substance.tolerance != nil || !substance.crossTolerances.isEmpty {
          ToleranceSection(substance: substance)
        }
        ToxicitySection(substance: substance, anodyne: anodyne)
      }
      Group {
        if let acute = substance.generalRisks {
          Section("Acute Risk") { Text(acute) }
        }
        if let longTerm = substance.longtermRisks {
          Section("Long-term Risk") { Text(longTerm) }
        }
        if let anodyne {
          AnodyneWarningsSection(anodyne: anodyne)
        }
        if !substance.saferUse.isEmpty {
          Section("Safer Use") {
            ForEach(substance.saferUse, id: \.self) { point in Text(point) }
          }
        }
        if let addictionPotential = substance.addictionPotential {
          Section("Addiction Potential") { Text(addictionPotential) }
        }
      }
      if let anodyne {
        AnodyneReagentsSection(anodyne: anodyne)
        AnodyneLegalStatusSection(anodyne: anodyne)
        AnodynePharmacologySection(anodyne: anodyne)
      }
      SourcesSection(
        psychonautWikiURL: substance.url,
        anodyne: anodyne,
        isMissingOnAnodyne: anodyneModel.phase == .notFound
      )
    }
    .task {
      await anodyneModel.start()
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        NavigationLink("Article", value: GlobalNavigationDestination.webView(articleURL: substance.url))
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          isShowingCustomizeSheet = true
        } label: {
          Label("Customize", systemImage: "slider.horizontal.3")
        }
      }
    }
    .sheet(isPresented: $isShowingCustomizeSheet) {
      SubstanceCustomizeSheet(substance: substance)
    }
    .navigationTitle(substance.displayName)
  }

  // AnodyneWiki's timings fill in routes without PsychonautWiki or custom durations
  private var hasAnodyneTimings: Bool {
    let timings = AnodyneFallbackStore.shared
    return !timings.routesWithTimings(for: substance.name).isEmpty
      || substance.roas.contains { timings.duration(for: substance.name, route: $0.name) != nil }
  }

  private func overviewSection(anodyne: AnodyneSubstance?) -> some View {
    let categories = PersistenceController.shared.categories(for: substance.name)
    let shownNames = Set([substance.name, substance.displayName, anodyne?.title].compactMap { $0?.lowercased() })
    let otherNames = (substance.commonNames + (anodyne?.abbreviations ?? []) + (anodyne?.slang ?? []))
      .uniqued()
      .filter { !shownNames.contains($0.lowercased()) }
    return Section {
      if let summary = substance.summary {
        Text(summary)
      }
      if !categories.isEmpty {
        CategorySection(categoryNames: categories)
      }
      if let anodyne {
        AnodyneChemistryRows(anodyne: anodyne, substanceName: substance.displayName)
      }
      if !otherNames.isEmpty {
        DetailRow(title: "Also Known As", text: otherNames.prefix(12).joined(separator: ", "))
      }
    } header: {
      Text("Overview")
    } footer: {
      if !substance.isApproved {
        Text("This information hasn't been approved by PsychonautWiki's moderators.")
      }
    }
  }
}

// MARK: - SubstanceCustomizeSheet

struct SubstanceCustomizeSheet: View {
  let substance: Substance
  @Environment(\.dismiss) private var dismiss
  @State private var displayName = ""

  var body: some View {
    NavigationStack {
      List {
        Section {
          TextField(substance.name, text: $displayName)
            .autocorrectionDisabled()
            .onSubmit(saveDisplayName)
        } header: {
          Text("Name")
        } footer: {
          Text(
            "Shown instead of \(substance.name) in your journal, stats, search and webhooks. "
              + "Your data stays linked to \(substance.name), so its dose, duration and interaction info keep working."
          )
        }
        Section {
          NavigationLink("Categories") {
            EditCategoriesScreen(substanceName: substance.name)
          }
        }
        Section {
          CustomRoaRouteList(substanceName: substance.name)
        } header: {
          Text("Override Dose & Duration")
        } footer: {
          Text(
            "Routes open with the PsychonautWiki data filled in. "
              + "Your changes take priority over it in the timeline and dose display."
          )
        }
      }
      .navigationTitle(substance.displayName)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
      }
      .onAppear {
        displayName = PersistenceController.shared.substanceOverride(for: substance.name)?.displayName ?? ""
      }
      .onDisappear(perform: saveDisplayName)
    }
  }

  private func saveDisplayName() {
    let override = PersistenceController.shared.substanceOverride(for: substance.name)
    guard displayName != override?.displayName ?? "" else { return }
    PersistenceController.shared.setSubstanceOverride(
      for: substance.name,
      displayName: displayName,
      categories: override?.categories
    )
  }
}

#Preview {
  NavigationStack {
    SubstanceScreen(substance: SubstanceRepo.shared.getSubstance(name: "MDMA")!)
  }
}
