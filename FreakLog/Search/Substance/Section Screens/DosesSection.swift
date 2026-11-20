import SwiftUI

struct DosesSection: View {
  init(substance: Substance) {
    self.substance = substance
    customUnits = FetchRequest(fetchRequest: PersistenceController.activeCustomUnitsRequest(for: substance.name))
    customRoas = FetchRequest(fetchRequest: PersistenceController.standaloneCustomRoasRequest(for: substance.name))
  }

  let substance: Substance
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

  var body: some View {
    Group {
      Section {
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
      } header: {
        HStack {
          Text("Dose")
          Spacer()
          Button("Disclaimer") {
            isDisclaimerShown = true
          }
        }
      }
      .alert(
        "Dosage Disclaimer",
        isPresented: $isDisclaimerShown) {
          Button("Ok") {
            isDisclaimerShown = false
          }
        } message: {
          Text(ChooseDoseScreenContent.doseDisclaimer)
        }

      if substance.name == "MDMA" {
        Section("Oral Max Dose Calculator") {
          MDMAMaxDoseCalculator(showResult: true, onChangeOfMax: { _ in })
        }
        MDMAOptimalDoseSection()
        MDMAPillsSection()
      }
      if substance.roas.contains(where: { $0.name == .smoked }), substance.categories.contains("opioid") {
        ChasingTheDragonSection()
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
