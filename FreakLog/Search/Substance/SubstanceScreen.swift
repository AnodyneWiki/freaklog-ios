import SwiftUI

struct SubstanceScreen: View {
  let substance: Substance

  @State private var isShowingCustomizeSheet = false
  @FetchRequest private var customRoas: FetchedResults<CustomRoa>
  // Redraws the screen when the user's name or categories for the substance change
  @FetchRequest private var overrides: FetchedResults<SubstanceOverride>

  init(substance: Substance) {
    self.substance = substance
    _customRoas = FetchRequest(fetchRequest: PersistenceController.customRoasRequest(for: substance.name))
    let overridesRequest = PersistenceController.substanceOverridesRequest()
    overridesRequest.predicate = NSPredicate(format: "substanceName == %@", substance.name)
    _overrides = FetchRequest(fetchRequest: overridesRequest)
  }

  var body: some View {
    let categories = PersistenceController.shared.categories(for: substance.name)
    List {
      if !substance.isApproved {
        Section {
          Text("Info Not PW Approved")
        }
      }
      Group {
        Group {
          if let summary = substance.summary {
            Section("Summary") {
              VStack {
                Text(summary)
                if !categories.isEmpty {
                  CategorySection(categoryNames: categories)
                }
              }
            }
          } else {
            if !categories.isEmpty {
              Section("Categories") {
                CategorySection(categoryNames: categories)
              }
            }
          }
          if let effects = substance.effectsSummary {
            Section("Effects") {
              Text(effects)
            }
          }
        }
        Group {
          if substance.dosageRemark != nil || !substance.doseInfos.isEmpty || customRoas.contains(where: { $0.roaDose != nil }) {
            DosesSection(substance: substance)
          }
          if !substance.durationInfos.isEmpty || customRoas.contains(where: { $0.roaDuration != nil }) {
            DurationSection(substance: substance)
          }
          if let interactions = substance.interactions {
            Section("Interactions") {
              InteractionsGroup(interactions: interactions, substance: substance)
            }
          }
          if substance.tolerance != nil || !substance.crossTolerances.isEmpty {
            ToleranceSection(substance: substance)
          }
          if !substance.toxicities.isEmpty {
            ToxicitySection(substance: substance)
          }
        }
        Group {
          if let acute = substance.generalRisks {
            Section("Acute Risk") { Text(acute) }
          }
          if let longTerm = substance.longtermRisks {
            Section("Long-term Risk") { Text(longTerm) }
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
      }
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
        displayName = PersistenceController.shared.getSubstanceOverride(for: substance.name)?.trimmedDisplayName ?? ""
      }
      .onDisappear(perform: saveDisplayName)
    }
  }

  private func saveDisplayName() {
    let override = PersistenceController.shared.getSubstanceOverride(for: substance.name)
    guard displayName != override?.trimmedDisplayName ?? "" else { return }
    PersistenceController.shared.setSubstanceOverride(
      for: substance.name,
      displayName: displayName,
      categories: override?.categoryList
    )
  }
}

#Preview {
  NavigationStack {
    SubstanceScreen(substance: SubstanceRepo.shared.getSubstance(name: "MDMA")!)
  }
}
