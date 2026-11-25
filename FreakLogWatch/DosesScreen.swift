import SwiftUI

// The doses recently logged for a suggestion: tapping one logs it now
struct DosesScreen: View {
  let suggestion: WatchSuggestion

  var body: some View {
    List {
      Section {
        ForEach(suggestion.doses, id: \.self) { dose in
          let calculated = suggestion.calculatedDescription(of: dose)
          Button {
            model.log(dose, of: suggestion)
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text(suggestion.description(of: dose))
                .font(.title3.weight(.semibold))
              if let calculated {
                Text(calculated)
                  .font(.footnote)
                  .foregroundStyle(.secondary)
              }
            }
            .padding(.vertical, 2)
          }
          .accessibilityLabel("Log \(suggestion.description(of: dose))")
          .accessibilityValue(calculated ?? "")
        }
      } header: {
        Text(suggestion.routeName)
      } footer: {
        Text(suggestion.formulation == nil ? "Logs the dose now." : "Logs each substance now.")
      }
      Section {
        NavigationLink(value: QuickLogDestination.otherDose(suggestion)) {
          Label(suggestion.formulation == nil ? "Other Dose" : "Other Amount", systemImage: "digitalcrown.horizontal.arrow.clockwise")
        }
      }
    }
    .navigationTitle(suggestion.title)
    .tint(suggestion.swiftUIColor)
  }

  @EnvironmentObject private var model: QuickLogModel

}
