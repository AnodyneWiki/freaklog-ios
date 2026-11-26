import CoreData
import SwiftUI

// Where the dose section's ranges come from, when both sources have some
enum DoseSource: String, CaseIterable {
  case psychonautWiki, anodyneWiki

  var title: String {
    switch self {
    case .psychonautWiki: "PsychonautWiki"
    case .anodyneWiki: "AnodyneWiki"
    }
  }
}

// The dose ranges per route from PsychonautWiki (with the user's own overrides and custom units), or
// AnodyneWiki's dose tiers from logged doses; a segmented control switches when both have some
struct DosesSection: View {
  init(substance: Substance, anodyne: AnodyneSubstance? = nil) {
    self.substance = substance
    self.anodyne = anodyne
    customUnits = FetchRequest(fetchRequest: PersistenceController.activeCustomUnitsRequest(for: substance.name))
    customRoas = FetchRequest(fetchRequest: PersistenceController.customRoasRequest(for: substance.name))
  }

  let substance: Substance
  let anodyne: AnodyneSubstance?
  @AppStorage(PersistenceController.doseSourceKey) private var preferredSource = DoseSource.psychonautWiki
  @State private var isDisclaimerShown = false
  private var customUnits: FetchRequest<CustomUnit>
  private var customRoas: FetchRequest<CustomRoa>

  private var routesToShow: [AdministrationRoute] {
    var routes = substance.doseInfos.map { $0.route }
    let pwRoutes = Set(routes)
    for roa in customRoas.wrappedValue where roa.roaDose != nil {
      let route = roa.administrationRouteUnwrapped
      if !pwRoutes.contains(route) {
        routes.append(route)
      }
    }
    return routes
  }

  private var hasPsychonautWikiDoses: Bool {
    substance.dosageRemark != nil || !routesToShow.isEmpty
  }

  private var anodyneDosing: [AnodyneSubstance.Dosing] {
    anodyne?.dosing ?? []
  }

  // The preferred source, unless only the other one has doses
  private var source: DoseSource {
    if anodyneDosing.isEmpty { return .psychonautWiki }
    if !hasPsychonautWikiDoses { return .anodyneWiki }
    return preferredSource
  }

  var body: some View {
    Group {
      Section {
        if hasPsychonautWikiDoses, !anodyneDosing.isEmpty {
          Picker("Source", selection: $preferredSource) {
            ForEach(DoseSource.allCases, id: \.self) { source in
              Text(source.title).tag(source)
            }
          }
          .pickerStyle(.segmented)
          .listRowSeparator(.hidden)
        }
        switch source {
        case .psychonautWiki:
          psychonautWikiRows
        case .anodyneWiki:
          ForEach(anodyneDosing, id: \.method) { dosing in
            AnodyneDosingRow(dosing: dosing)
          }
        }
      } header: {
        HStack {
          Text("Dose")
          Spacer()
          Button("Disclaimer") {
            isDisclaimerShown = true
          }
        }
      } footer: {
        if source == .anodyneWiki {
          Text(AnodyneDosingRow.disclaimer)
        }
      }
      .alert(
        "Dosage Disclaimer",
        isPresented: $isDisclaimerShown) {
          Button("Ok") {
            isDisclaimerShown = false
          }
        } message: {
          Text(ChooseDoseScreen.doseDisclaimer)
        }

      if substance.name == "MDMA" {
        Section("Oral Max Dose Calculator") {
          MDMAMaxDoseCalculator(showResult: true, onChangeOfMax: { _ in })
        }
        MDMAOptimalDoseSection()
        MDMAPillsSection()
      }
      let isOpioid = PersistenceController.shared.categories(for: substance.name).contains("opioid")
      if substance.roas.contains(where: { $0.name == .smoked }), isOpioid {
        ChasingTheDragonSection()
      }
    }
  }

  @ViewBuilder
  private var psychonautWikiRows: some View {
    if let remark = substance.dosageRemark {
      Text(remark)
    }
    ForEach(routesToShow, id: \.self) { route in
      let roaDose = PersistenceController.shared.resolvedDose(for: substance.name, route: route)
      if let roaDose {
        VStack(alignment: .leading, spacing: 8) {
          Text(route.rawValue.localizedCapitalized).font(.headline)
          RoaDoseRow(roaDose: roaDose)
          let customUnitsForRoa = customUnits.wrappedValue.filter { cu in
            cu.administrationRouteUnwrapped == route && cu.doseUnwrapped != nil
          }
          ForEach(customUnitsForRoa) { customUnit in
            Text(customUnit.nameUnwrapped).font(.headline)
            CustomUnitDoseRow(customUnit: customUnit.minInfo, roaDose: roaDose)
          }
          if let bio = substance.doseInfos.first(where: { $0.route == route })?.bioavailability?.displayString {
            RowLabelView(label: "Bioavailability", value: "\(bio)%")
          }
        }
      }
    }
  }

  static func getUnitClarification(for units: String) -> String? {
    if units == "µg" {
      "1 µg = 1/1000 mg = 1/1'000'000 gram"
    } else if units == "mg" {
      "1 mg = 1/1000 gram"
    } else if units == "mL" {
      "1 mL = 1/1000 L"
    } else {
      nil
    }
  }
}

#Preview {
  List {
    DosesSection(substance: SubstanceRepo.shared.getSubstance(name: "Amphetamine")!)
  }
}

#Preview {
  List {
    DosesSection(substance: SubstanceRepo.shared.getSubstance(name: "MDMA")!)
  }
}
