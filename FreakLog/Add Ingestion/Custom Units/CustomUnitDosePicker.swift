import SwiftUI

struct CustomUnitDosePicker: View {

    let customUnit: CustomUnit
    @Binding var dose: Double?
    @Binding var isEstimate: Bool
    @Binding var estimatedDoseStandardDeviation: Double?

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
            EstimateFields(
                isEstimate: $isEstimate,
                standardDeviation: $estimatedDoseStandardDeviation,
                units: customUnit.unitUnwrapped,
                mean: dose
            )
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
