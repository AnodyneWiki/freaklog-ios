import SwiftUI

struct CustomUnitDosePicker: View {

    let customUnit: CustomUnit
    @Binding var dose: Double?
    @Binding var isEstimate: Bool
    @Binding var estimatedDoseStandardDeviation: Double?

    @FocusState private var isEstimatedDeviationFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CustomUnitDoseRow(customUnit: customUnit.minInfo, roaDose: customUnit.roaDose)
            HStack {
                TextField(
                    "Enter Dose",
                    value: $dose,
                    format: .number
                )
                .keyboardType(.decimalPad)
                Text((dose ?? 0).justUnit(pluralizableUnit: customUnit.pluralizableUnit))
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
                        "Estimated standard deviation",
                        value: $estimatedDoseStandardDeviation,
                        format: .number
                    )
                    .keyboardType(.decimalPad)
                    .focused($isEstimatedDeviationFocused)
                    Spacer()
                    Text(customUnit.unitUnwrapped)
                }
            }
            if let dose, let estimatedDoseStandardDeviation {
                StandardDeviationConfidenceIntervalExplanation(mean: dose, standardDeviation: estimatedDoseStandardDeviation, unit: customUnit.unitUnwrapped)
            }
        }
    }
}

struct CustomUnitsDosePickerPreviewContainer: View {

    @State private var dose: Double? = 3.0
    @State private var isEstimate = false
    @State private var estimatedDoseStandardDeviation: Double? = 0.5

    var body: some View {
        CustomUnitDosePicker(
            customUnit: .estimatedQuantitativelyPreviewSample,
            dose: $dose,
            isEstimate: $isEstimate,
            estimatedDoseStandardDeviation: $estimatedDoseStandardDeviation)
    }
}

#Preview {
    CustomUnitsDosePickerPreviewContainer()
}
