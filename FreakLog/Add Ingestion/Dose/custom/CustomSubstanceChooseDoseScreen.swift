import SwiftUI

struct CustomSubstanceChooseDoseScreen: View {
    let arguments: CustomChooseDoseScreenArguments
    let dismiss: () -> Void
    @State private var doseText = ""
    @State private var dose: Double?
    @State private var isEstimate = false
    @State private var doseDeviation: Double?
    @FocusState private var isDoseFieldFocused: Bool

    @FetchRequest(
        sortDescriptors: []
    ) private var customSubstances: FetchedResults<CustomSubstance>

    private var customSubstance: CustomSubstance? {
        customSubstances.first { substance in
            substance.nameUnwrapped == arguments.substanceName
        }
    }

    var body: some View {
        screen.toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                nextLink
            }
        }
    }

    private var nextLink: some View {
        NavigationLink(value: getDestinationArguments(dose: dose)) {
            NextLabel()
        }
    }

    func getDestinationArguments(dose: Double?) -> FinishIngestionScreenArguments {
        FinishIngestionScreenArguments(
            substanceName: arguments.substanceName,
            administrationRoute: arguments.administrationRoute,
            dose: dose,
            units: arguments.units,
            isEstimate: isEstimate,
            estimatedDoseStandardDeviation: doseDeviation
        )
    }

    @FocusState private var isEstimatedDeviationFocused: Bool

    private var screen: some View {
        Form {
            if let explanationUnwrapped = customSubstance?.explanation, !explanationUnwrapped.isEmpty {
                Section {
                    Text(explanationUnwrapped)
                }
            }
            Section {
                HStack {
                    TextField("Enter Dose", text: $doseText)
                        .focused($isDoseFieldFocused)
                        .keyboardType(.decimalPad)
                        .onChange(of: doseText) { text in
                            dose = getDouble(from: text)
                        }
                    Text(arguments.units)
                }
                .font(.title)
                Toggle("Estimate", isOn: $isEstimate)
                    .tint(.accentColor)
                    .onChange(of: isEstimate, perform: { newIsEstimate in
                        if newIsEstimate {
                            isEstimatedDeviationFocused = true
                        }
                    })
                if isEstimate {
                    HStack {
                        Image(systemName: "plusminus")
                        TextField(
                            "Pure dose standard deviation",
                            value: $doseDeviation,
                            format: .number
                        )
                        .keyboardType(.decimalPad)
                        .focused($isEstimatedDeviationFocused)
                        Spacer()
                        Text(arguments.units)
                    }
                }
                if let dose, let doseDeviation {
                    StandardDeviationConfidenceIntervalExplanation(mean: dose, standardDeviation: doseDeviation, unit: arguments.units)
                }
            }.listRowSeparator(.hidden)
        }
        .task {
            isDoseFieldFocused = true
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("\(arguments.substanceName) Dose")
    }
}

#Preview {
    NavigationStack {
        CustomSubstanceChooseDoseScreen(
            arguments: .init(substanceName: "Coffee",
                             units: "cups",
                             administrationRoute: .oral),
            dismiss: {}
        )
    }
}
