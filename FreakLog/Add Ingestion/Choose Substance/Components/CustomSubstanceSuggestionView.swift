import SwiftUI
import WrappingHStack

struct CustomSubstanceSuggestionView: View {

    let customSubstanceSuggestions: CustomSubstanceSuggestions
    let isEyeOpen: Bool

    var body: some View {
        VStack(alignment: .leading) {
            let administrationRoute = customSubstanceSuggestions.administrationRoute
            let routeText = isEyeOpen ? administrationRoute.rawValue.localizedCapitalized : ""
            Label(
                "\(customSubstanceSuggestions.customSubstanceName) \(routeText)",
                systemImage: "circle.fill")
            .font(.headline)
            .foregroundColor(customSubstanceSuggestions.substanceColor.swiftUIColor)
            WrappingHStack(
                alignment: .leading,
                horizontalSpacing: horizontalSpacing,
                verticalSpacing: verticalSpacing)
            {
                ForEach(customSubstanceSuggestions.dosesAndUnit) { doseAndUnit in
                    if let doseDescription = doseAndUnit.doseDescription {
                        NavigationLink(
                            doseDescription,
                            value: FinishIngestionScreenArguments(
                                substanceName: customSubstanceSuggestions.customSubstanceName,
                                administrationRoute: administrationRoute,
                                dose: doseAndUnit.dose,
                                units: doseAndUnit.units,
                                isEstimate: doseAndUnit.isEstimate,
                                estimatedDoseStandardDeviation: doseAndUnit.estimatedDoseStandardDeviation))
                        .buttonStyle(.bordered).fixedSize()
                    } else {
                        NavigationLink("Unknown", value: FinishIngestionScreenArguments(
                            substanceName: customSubstanceSuggestions.customSubstanceName,
                            administrationRoute: administrationRoute,
                            dose: doseAndUnit.dose,
                            units: doseAndUnit.units,
                            isEstimate: doseAndUnit.isEstimate,
                            estimatedDoseStandardDeviation: nil
                        ))
                        .buttonStyle(.bordered).fixedSize()
                    }
                }
                if let units = customSubstanceSuggestions.dosesAndUnit.first?.units {
                    NavigationLink("Other dose", value: SubstanceAndRoute(
                        substance: .custom(name: customSubstanceSuggestions.customSubstanceName, units: units),
                        administrationRoute: administrationRoute))
                    .buttonStyle(.borderedProminent).fixedSize()
                }
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

#Preview {
    NavigationStack {
        CustomSubstanceSuggestionView(customSubstanceSuggestions: CustomSubstanceSuggestions(administrationRoute: .oral, customSubstanceName: "Amanita muscaria", dosesAndUnit: [
            RegularDoseAndUnit(dose: 3, units: "g", isEstimate: false, estimatedDoseStandardDeviation: nil),
            RegularDoseAndUnit(dose: 4, units: "g", isEstimate: true, estimatedDoseStandardDeviation: 1)
        ], substanceColor: .orange, sortDate: .now), isEyeOpen: true)
    }
}
