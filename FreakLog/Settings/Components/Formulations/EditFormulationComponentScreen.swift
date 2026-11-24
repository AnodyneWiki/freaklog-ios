import SwiftUI

// MARK: - EditFormulationComponentScreen

// The route and dose of one substance in a formulation, for one unit of the formulation
struct EditFormulationComponentScreen: View {

  init(
    substance: AddIngestionSubstance,
    component: FormulationCodable.Component?,
    onDone: @escaping (FormulationCodable.Component) -> Void)
  {
    self.substance = substance
    self.component = component
    self.onDone = onDone
    let route = component?.administrationRoute ?? substance.documentedRoutes.first ?? .oral
    let roaDose = PersistenceController.shared.resolvedDose(for: substance.name, route: route)
    _route = State(initialValue: route)
    _dose = State(initialValue: component?.dose)
    let defaultUnits = substance.customSubstanceUnits ?? UnitPickerOptions.mg.rawValue
    _units = State(initialValue: component?.units ?? roaDose?.units ?? defaultUnits)
    _isEstimate = State(initialValue: component?.isEstimate ?? false)
    _estimatedDoseStandardDeviation = State(initialValue: component?.estimatedDoseStandardDeviation)
  }

  let substance: AddIngestionSubstance
  let component: FormulationCodable.Component?
  let onDone: (FormulationCodable.Component) -> Void

  var body: some View {
    Form {
      Section("Route") {
        Picker("Route", selection: $route) {
          ForEach(routes, id: \.self) { route in
            Text(route.rawValue.localizedCapitalized).tag(route)
          }
        }
      }
      Section {
        VStack(alignment: .leading) {
          if let roaDose {
            RoaDoseRow(roaDose: roaDose)
          }
          DosePicker(roaDose: roaDose, doseMaybe: $dose, selectedUnits: $units)
          EstimateFields(
            isEstimate: $isEstimate,
            standardDeviation: $estimatedDoseStandardDeviation,
            units: units,
            mean: dose)
        }
      } header: {
        Text("Pure Dose")
      } footer: {
        Text("The dose in one unit of the formulation, e.g. one pill. Leave it empty if unknown.")
      }
      .listRowSeparator(.hidden)
    }
    .scrollDismissesKeyboard(.interactively)
    .navigationTitle(substance.displayName)
    .onChange(of: route) { newRoute in
      if let routeUnits = PersistenceController.shared.resolvedDose(for: substance.name, route: newRoute)?.units {
        units = routeUnits
      }
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        DoneButton {
          var newComponent = FormulationCodable.Component(
            substanceName: substance.name,
            administrationRoute: route,
            dose: dose,
            units: units,
            isEstimate: isEstimate,
            estimatedDoseStandardDeviation: isEstimate ? estimatedDoseStandardDeviation : nil)
          if let component {
            newComponent.id = component.id
          }
          onDone(newComponent)
        }
        .disabled(units.isEmpty)
      }
    }
  }

  @State private var route: AdministrationRoute
  @State private var dose: Double?
  @State private var units: String
  @State private var isEstimate: Bool
  @State private var estimatedDoseStandardDeviation: Double?

  private var roaDose: RoaDose? {
    PersistenceController.shared.resolvedDose(for: substance.name, route: route)
  }

  // Documented routes first
  private var routes: [AdministrationRoute] {
    let documentedRoutes = substance.documentedRoutes
    return documentedRoutes + AdministrationRoute.allCases.filter { !documentedRoutes.contains($0) }
  }
}

#Preview {
  NavigationStack {
    EditFormulationComponentScreen(
      substance: .psychonautWiki(SubstanceRepo.shared.getSubstance(name: "MDMA")!),
      component: nil,
      onDone: { _ in })
  }
}
