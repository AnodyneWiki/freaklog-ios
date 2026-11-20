import SwiftUI

struct CustomSubstanceChooseDoseScreen: View {
  let arguments: CustomChooseDoseScreenArguments
  let dismiss: () -> Void
  let navigateToCustomUnitChooseDose: (CustomUnit) -> Void
  @State private var selectedUnits: String
  @State private var selectedPureDose: Double?
  @State private var selectedDoseDeviation: Double?
  @State private var isEstimate = false
  @State private var isShowingNext = false

  @AppStorage(PersistenceController.isEyeOpenKey2) var isEyeOpen = false

  init(
    arguments: CustomChooseDoseScreenArguments,
    dismiss: @escaping () -> Void,
    navigateToCustomUnitChooseDose: @escaping (CustomUnit) -> Void
  ) {
    self.arguments = arguments
    self.dismiss = dismiss
    self.navigateToCustomUnitChooseDose = navigateToCustomUnitChooseDose
    _selectedUnits = State(initialValue: arguments.units)
  }

  var body: some View {
    let description = PersistenceController.shared
      .getCustomSubstance(name: arguments.substanceName)?.explanationUnwrapped
    ChooseDoseScreenContent(
      substanceName: arguments.substanceName,
      substance: nil,
      customSubstanceDescription: description?.isEmpty == false ? description : nil,
      defaultUnits: arguments.units,
      administrationRoute: arguments.administrationRoute,
      dismiss: dismiss,
      navigateToCustomUnitChooseDose: navigateToCustomUnitChooseDose,
      isEyeOpen: isEyeOpen,
      selectedPureDose: $selectedPureDose,
      selectedDoseDeviation: $selectedDoseDeviation,
      selectedUnits: $selectedUnits,
      isEstimate: $isEstimate,
      isShowingNext: $isShowingNext)
      .task {
        let routeUnits = PersistenceController.shared
          .resolvedDose(for: arguments.substanceName, route: arguments.administrationRoute)?.units
        if let routeUnits {
          selectedUnits = routeUnits
        }
      }
  }
}
