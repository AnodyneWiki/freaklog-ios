import SwiftUI

// MARK: - FinishFormulationArguments

// The ingestions of a formulation, logged together by the finish screen
struct FinishFormulationArguments: Hashable {
  let ingestions: [FinishIngestionScreenArguments]
}

// MARK: - FormulationDoseScreen

// Chooses how much of a formulation was taken, e.g. 1.5 pills, which scales the dose of every substance in it
struct FormulationDoseScreen: View {

  init(
    formulation: Formulation, dismiss: @escaping () -> Void, showsProductLink: Bool = true, initialAmount: Double? = 1
  ) {
    self.formulation = formulation
    self.dismiss = dismiss
    self.showsProductLink = showsProductLink
    _amount = State(initialValue: initialAmount)
  }

  let dismiss: () -> Void
  let showsProductLink: Bool
  @AppStorage(PersistenceController.isEyeOpenKey2) private var isEyeOpen = false

  var body: some View {
    let values = FormulationCodable(formulation)
    let arguments = validAmount.map { formulation.ingestionArguments(amount: $0) } ?? []
    let interactions = ExperienceLogic.interactions(between: values.substanceNames)
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
      Section {
        if validAmount != nil, arguments.isEmpty {
          Text("The ingredients can’t be scaled to this amount.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(values.components) { component in
            FormulationComponentDoseRow(component: component, amount: validAmount ?? 1)
          }
        }
      } header: {
        Text("Substances")
      } footer: {
        if validAmount == nil {
          Text("Ingredient amounts are shown per serving until you enter the amount you took.")
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
      if isEyeOpen, showsProductLink {
        Section {
          NavigationLink {
            ProductDetailScreen(product: .formulation(formulation), allowsLogging: false)
          } label: {
            Label("View Product", systemImage: "shippingbox")
          }
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
        NavigationLink(value: FinishFormulationArguments(ingestions: arguments)) {
          NextLabel()
        }
        .disabled(arguments.isEmpty)
      }
    }
  }

  @State private var amount: Double?

  @ObservedObject private var formulation: Formulation

  private var validAmount: Double? {
    guard let amount, amount.isFinite, amount > 0 else { return nil }
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
      if !component.blendPath.isEmpty {
        Text(component.blendPath.map(\.name).joined(separator: " › "))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
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
