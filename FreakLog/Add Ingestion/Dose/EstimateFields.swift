import SwiftUI

// "Estimate" toggle with a ± standard deviation field that gets focus when the toggle is turned on.
// Pass the mean to also explain the resulting confidence interval.
struct EstimateFields: View {
    @Binding var isEstimate: Bool
    @Binding var standardDeviation: Double?
    let units: String
    var mean: Double?

    @FocusState private var isDeviationFocused: Bool

    var body: some View {
        Toggle("Estimate", isOn: $isEstimate.animation())
            .tint(.accentColor)
            .onChange(of: isEstimate) { newIsEstimate in
                if newIsEstimate {
                    isDeviationFocused = true
                }
            }
        if isEstimate {
            HStack {
                Image(systemName: "plusminus")
                TextField("Estimated standard deviation", value: $standardDeviation, format: .number)
                    .keyboardType(.decimalPad)
                    .focused($isDeviationFocused)
                Spacer()
                Text(units)
            }
            if let mean, let standardDeviation {
                StandardDeviationConfidenceIntervalExplanation(mean: mean, standardDeviation: standardDeviation, unit: units)
            }
        }
    }
}

#Preview {
    Form {
        EstimateFields(isEstimate: .constant(true), standardDeviation: .constant(5), units: "mg", mean: 20)
    }
}
