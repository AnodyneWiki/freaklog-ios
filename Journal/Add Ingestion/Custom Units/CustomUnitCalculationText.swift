import SwiftUI

struct CustomUnitCalculationText: View {

    let customUnit: CustomUnit
    let dose: Double?
    let isEstimate: Bool
    let estimatedDoseStandardDeviation: Double?

    var body: some View {
        VStack(alignment: .leading) {
            doseCalculationText
            if let calculatedDose = customUnitDose?.calculatedDose, let calculatedStandardDeviation = customUnitDose?.calculatedStandardDeviation {
                Text("Meaning ") + Text(StandardDeviationConfidenceIntervals.getTwoStandardDeviationText(mean: calculatedDose, standardDeviation: calculatedStandardDeviation, unit: customUnit.originalUnitUnwrapped))
            }
        }.foregroundStyle(calculatedDoseColor)
    }

    private var customUnitDose: CustomUnitDose? {
        if let dose {
            return CustomUnitDose(
                dose: dose,
                isEstimate: isEstimate,
                estimatedStandardDeviation: estimatedDoseStandardDeviation,
                customUnit: customUnit)
        } else {
            return nil
        }
    }

    private var calculatedDoseColor: Color {
        if let calculatedDose = customUnitDose?.calculatedDose {
            customUnit.roaDose?.getRangeType(for: calculatedDose, with: customUnit.originalUnitUnwrapped).color ?? Color.primary
        } else {
            Color.primary
        }
    }

    private var doseCalculationText: Text {
        if let customUnitDose, let calculatedDoseDescription = customUnitDose.calculatedDoseDescription {
            Text(calculatedDoseDescription).fontWeight(.bold) +
            Text(
                " = \(customUnitDose.doseDescription) x \(customUnit.doseOfOneUnitDescription)")
        } else {
            Text(" ")
        }
    }
}

#Preview {
    CustomUnitCalculationText(
        customUnit: .estimatedQuantitativelyPreviewSample,
        dose: 3.0,
        isEstimate: true,
        estimatedDoseStandardDeviation: 0.5)
}
