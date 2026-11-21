import SwiftUI
import WrappingHStack

struct PureSubstanceSuggestionView: View {

    let pureSubstanceSuggestions: PureSubstanceSuggestions
    let isEyeOpen: Bool

    var body: some View {
        VStack(alignment: .leading) {
            let routeText = isEyeOpen ? pureSubstanceSuggestions.route.rawValue.localizedCapitalized : ""
            Label(
                "\(pureSubstanceSuggestions.substance.displayName) \(routeText)",
                systemImage: "circle.fill")
            .font(.headline)
            .foregroundColor(pureSubstanceSuggestions.substanceColor.swiftUIColor)
            WrappingHStack(
                alignment: .leading,
                horizontalSpacing: horizontalSpacing,
                verticalSpacing: verticalSpacing)
            {
                ForEach(pureSubstanceSuggestions.dosesAndUnit) { doseAndUnit in
                    if let doseDescription = doseAndUnit.doseDescription {
                        NavigationLink(
                            doseDescription,
                            value: FinishIngestionScreenArguments(
                                substanceName: pureSubstanceSuggestions.substance.name,
                                administrationRoute: pureSubstanceSuggestions.route,
                                dose: doseAndUnit.dose,
                                units: doseAndUnit.units,
                                isEstimate: doseAndUnit.isEstimate,
                                estimatedDoseStandardDeviation: doseAndUnit.estimatedDoseStandardDeviation))
                        .buttonStyle(.bordered).fixedSize()
                    } else {
                        NavigationLink("Unknown", value: FinishIngestionScreenArguments(
                            substanceName: pureSubstanceSuggestions.substance.name,
                            administrationRoute: pureSubstanceSuggestions.route,
                            dose: doseAndUnit.dose,
                            units: doseAndUnit.units,
                            isEstimate: doseAndUnit.isEstimate,
                            estimatedDoseStandardDeviation: nil
                        ))
                        .buttonStyle(.bordered).fixedSize()
                    }
                }
                NavigationLink(
                    "Other dose",
                    value: SubstanceAndRoute(
                        substance: .psychonautWiki(pureSubstanceSuggestions.substance),
                        administrationRoute: pureSubstanceSuggestions.route))
                .buttonStyle(.borderedProminent).fixedSize()
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
        PureSubstanceSuggestionView(
            pureSubstanceSuggestions: PureSubstanceSuggestions(route: .oral, substance: SubstanceRepo.shared.getSubstance(name: "MDMA")!, substanceColor: .pink, dosesAndUnit: [
                RegularDoseAndUnit(dose: 50, units: "mg", isEstimate: false, estimatedDoseStandardDeviation: nil),
                RegularDoseAndUnit(dose: 80, units: "mg", isEstimate: false, estimatedDoseStandardDeviation: nil),
                RegularDoseAndUnit(dose: 120, units: "mg", isEstimate: false, estimatedDoseStandardDeviation: nil),
                RegularDoseAndUnit(dose: 30, units: "mg", isEstimate: false, estimatedDoseStandardDeviation: nil),
                RegularDoseAndUnit(dose: 100, units: "mg", isEstimate: true, estimatedDoseStandardDeviation: 20)
            ], sortDate: .now),
            isEyeOpen: true)
    }
}
