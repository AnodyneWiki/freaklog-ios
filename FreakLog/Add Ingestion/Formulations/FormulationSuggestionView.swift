import SwiftUI
import WrappingHStack

// The amounts of a formulation taken recently: tapping one goes on to finish all its ingestions
struct FormulationSuggestionView: View {
  let formulationSuggestions: FormulationSuggestions

  var body: some View {
    let formulation = formulationSuggestions.formulation
    VStack(alignment: .leading) {
      Label(formulation.nameUnwrapped, systemImage: "circle.fill")
        .font(.headline)
        .foregroundColor(color.swiftUIColor)
      Text(formulation.componentsDescription)
        .font(.subheadline)
        .foregroundColor(.secondary)
      WrappingHStack(
        alignment: .leading,
        horizontalSpacing: horizontalSpacing,
        verticalSpacing: verticalSpacing)
      {
        ForEach(formulationSuggestions.amounts, id: \.self) { amount in
          NavigationLink(value: FinishFormulationArguments(ingestions: formulation.ingestionArguments(amount: amount))) {
            Text("\(amount.asRoundedReadableString)×")
          }
          .buttonStyle(.bordered)
          .fixedSize()
        }
        NavigationLink(value: formulation) {
          Text("Other amount")
        }
        .buttonStyle(.borderedProminent)
        .fixedSize()
      }
    }
    .padding(.top, 4)
    .padding(.bottom, 10)
    .padding(.horizontal)
    .overlay(alignment: .bottom) {
      Divider()
    }
  }

  private let horizontalSpacing: Double = 4
  private let verticalSpacing: Double = 5

  // The color of its first substance
  private var color: SubstanceColor {
    getColor(for: formulationSuggestions.formulation.componentsSorted.first?.substanceNameUnwrapped ?? "")
  }
}

#Preview {
  NavigationStack {
    FormulationSuggestionView(formulationSuggestions: FormulationSuggestions(
      formulation: .previewSample,
      amounts: [1, 0.5, 2],
      sortDate: .now))
  }
}
