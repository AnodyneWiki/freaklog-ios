import SwiftUI

// MARK: - FinishFormulationArguments

// The ingestions of a formulation, logged together by the finish screen
struct FinishFormulationArguments: Hashable {
  let ingestions: [FinishIngestionScreenArguments]
}

// MARK: - FormulationDoseScreen

// Chooses how much of a formulation was taken, e.g. 1.5 pills, which scales the dose of every substance in it
struct FormulationDoseScreen: View {

  init(formulation: Formulation, dismiss: @escaping () -> Void) {
    let values = FormulationCodable(formulation)
    self.values = values
    self.dismiss = dismiss
    interactions = ExperienceLogic.interactions(between: values.substanceNames)
  }

  let dismiss: () -> Void

  var body: some View {
    Form {
      Section {
        HStack {
          TextField("Amount", value: $amount, format: .number)
            .keyboardType(.decimalPad)
            .font(.title)
          Stepper("Amount", value: stepperAmount, in: 0.5 ... 100, step: 0.5)
            .labelsHidden()
        }
      } header: {
        Text("Amount")
      } footer: {
        Text("The doses of all substances are multiplied by the amount.")
      }
      Section("Substances") {
        ForEach(values.components) { component in
          FormulationComponentDoseRow(component: component, amount: validAmount ?? 0)
        }
      }
      if !interactions.isEmpty {
        Section("Interactions") {
          ForEach(interactions) { interaction in
            InteractionPairRow(
              aName: interaction.aName,
              bName: interaction.bName,
              interactionType: interaction.interactionType)
          }
        }
      }
      if !values.note.isEmpty {
        Section("Note") {
          Text(values.note)
        }
      }
    }
    .scrollDismissesKeyboard(.interactively)
    .navigationTitle(values.name)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel", action: dismiss)
      }
      ToolbarItem(placement: .primaryAction) {
        NavigationLink(value: FinishFormulationArguments(ingestions: values.ingestionArguments(amount: validAmount ?? 1))) {
          NextLabel()
        }
        .disabled(validAmount == nil)
      }
    }
  }

  @State private var amount: Double? = 1

  private let values: FormulationCodable
  private let interactions: [Interaction]

  private var validAmount: Double? {
    guard let amount, amount > 0 else { return nil }
    return amount
  }

  private var stepperAmount: Binding<Double> {
    Binding {
      amount ?? 0
    } set: { newAmount in
      amount = newAmount
    }
  }
}

// MARK: - FormulationComponentDoseRow

// One substance of a formulation with its dose for the amount, colored by its dose range
struct FormulationComponentDoseRow: View {
  let component: FormulationCodable.Component
  var amount: Double = 1

  var body: some View {
    VStack(alignment: .leading) {
      HStack {
        Image(systemName: "circle.fill")
          .font(.caption)
          .foregroundColor(getColor(for: component.substanceName).swiftUIColor)
        Text(PersistenceController.shared.displayName(for: component.substanceName)).font(.headline)
      }
      Text(component.doseDescription(amount: amount)).foregroundColor(doseRangeType.color)
        + Text(" \(component.administrationRoute.rawValue)").foregroundColor(.secondary)
    }
  }

  private var doseRangeType: DoseRangeType {
    guard let dose = component.ingestionArguments(amount: amount).dose else { return .none }
    return PersistenceController.shared
      .resolvedDose(for: component.substanceName, route: component.administrationRoute)?
      .getRangeType(for: dose, with: component.units) ?? .none
  }
}

#Preview {
  NavigationStack {
    FormulationDoseScreen(formulation: .previewSample, dismiss: { })
  }
}
