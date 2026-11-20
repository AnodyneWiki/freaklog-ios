import SwiftUI

struct SubstanceScreen: View {
  let substance: Substance

  @State private var isShowingAddIngestionSheet = false
  @State private var isShowingCustomizeSheet = false

  var body: some View {
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
                if !substance.categories.isEmpty {
                  CategorySection(substance: substance)
                }
              }
            }
          } else {
            if !substance.categories.isEmpty {
              Section("Categories") {
                CategorySection(substance: substance)
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
          if substance.dosageRemark != nil || !substance.doseInfos.isEmpty {
            DosesSection(substance: substance)
          }
          let durationInfos = substance.durationInfos
          if !durationInfos.isEmpty {
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
    .fullScreenCover(isPresented: $isShowingAddIngestionSheet) {
      NavigationStack {
        AcknowledgeInteractionsView(substance: substance) {
          isShowingAddIngestionSheet.toggle()
        }
      }
    }
    .sheet(isPresented: $isShowingCustomizeSheet) {
      SubstanceCustomizeSheet(substance: substance)
    }
    .navigationTitle(substance.name)
  }
}

// MARK: - SubstanceCustomizeSheet

struct SubstanceCustomizeSheet: View {
  let substance: Substance
  @Environment(\.dismiss) private var dismiss

  @FetchRequest private var customRoas: FetchedResults<CustomRoa>

  init(substance: Substance) {
    self.substance = substance
    _customRoas = FetchRequest(fetchRequest: PersistenceController.standaloneCustomRoasRequest(for: substance.name))
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(AdministrationRoute.allCases) { route in
            customizeRow(for: route)
          }
        } header: {
          Text("Override Dose & Duration")
        } footer: {
          Text("Custom data takes priority over PsychonautWiki values in the timeline and dose display.")
        }
      }
      .navigationTitle(substance.name)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }

  private func customizeRow(for route: AdministrationRoute) -> some View {
    let hasData = customRoas.first(where: { $0.administrationRouteUnwrapped == route })
      .map { $0.roaDose != nil || $0.roaDuration != nil } ?? false
    return NavigationLink(destination: EditCustomRoaView(substanceName: substance.name, route: route)) {
      HStack {
        Text(route.rawValue.localizedCapitalized)
        Spacer()
        if hasData {
          Image(systemName: "pencil.circle.fill").foregroundColor(.accentColor)
        }
      }
    }
  }
}

#Preview {
  NavigationStack {
    SubstanceScreen(substance: SubstanceRepo.shared.getSubstance(name: "MDMA")!)
  }
}
