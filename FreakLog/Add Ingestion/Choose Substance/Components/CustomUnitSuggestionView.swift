import SwiftUI
import WrappingHStack

struct CustomUnitSuggestionView: View {

    let customUnitSuggestions: CustomUnitSuggestions
    let isEyeOpen: Bool

    var body: some View {
        VStack(alignment: .leading) {
            let customUnit = customUnitSuggestions.customUnit
            let substanceName = customUnit.substanceNameUnwrapped
            let administrationRoute = customUnit.administrationRouteUnwrapped
            let routeText = isEyeOpen ? administrationRoute.rawValue.localizedCapitalized : ""
            Label(
                "\(customUnit.substanceDisplayName) \(routeText), \(customUnit.nameUnwrapped)",
                systemImage: "circle.fill")
            .font(.headline)
            .foregroundColor(customUnitSuggestions.substanceColor.swiftUIColor)
            WrappingHStack(
                alignment: .leading,
                horizontalSpacing: horizontalSpacing,
                verticalSpacing: verticalSpacing)
            {
                ForEach(customUnitSuggestions.doses) { customUnitDoseSuggestion in
                    NavigationLink(
                        value: FinishIngestionScreenArguments(
                            substanceName: substanceName,
                            administrationRoute: administrationRoute,
                            dose: customUnitDoseSuggestion.dose,
                            units: customUnit.originalUnitUnwrapped,
                            isEstimate: customUnitDoseSuggestion.isEstimate,
                            estimatedDoseStandardDeviation: customUnitDoseSuggestion.estimatedStandardDeviation,
                            customUnit: customUnit))
                    {
                        OneCustomUnitDoseSuggestionView(
                            customUnitDoseSuggestions: customUnitDoseSuggestion,
                            customUnit: customUnit
                        )
                    }.buttonStyle(.bordered).fixedSize()
                }
                NavigationLink(value: customUnit) {
                    Text("Other dose")
                }.buttonStyle(.borderedProminent).fixedSize()
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
}

private struct OneCustomUnitDoseSuggestionView: View {

    let customUnitDoseSuggestions: CustomUnitDoseSuggestion
    let customUnit: CustomUnit

    var body: some View {
        Text(doseDescription)
    }

    var doseDescription: String {
        if let dose = customUnitDoseSuggestions.dose {
            CustomUnitDose.description(
                of: dose,
                isEstimate: customUnitDoseSuggestions.isEstimate,
                standardDeviation: customUnitDoseSuggestions.estimatedStandardDeviation,
                customUnit: customUnit
            )
        } else {
            "Unknown"
        }
    }
}
