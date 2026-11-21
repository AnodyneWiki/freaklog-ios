import SwiftUI

struct CumulativeDoseRow: View {
    let substanceName: String
    let substanceColor: SubstanceColor
    let cumulativeRoutes: [CumulativeRouteAndDose]
    let isHidingDosageDots: Bool
    let isEyeOpen: Bool

    var body: some View {
        HStack {
            ColorRectangle(color: substanceColor.swiftUIColor)
            VStack(alignment: .leading) {
                Text(PersistenceController.shared.displayName(for: substanceName))
                    .font(.headline)
                    .foregroundColor(.primary)
                VStack {
                    ForEach(cumulativeRoutes) { routeItem in
                        RouteItemView(
                            routeItem: routeItem,
                            isHidingDosageDots: isHidingDosageDots,
                            isEyeOpen: isEyeOpen
                        )
                    }
                }
            }
        }
    }
}

struct RouteItemView: View {
    let routeItem: CumulativeRouteAndDose
    let isHidingDosageDots: Bool
    let isEyeOpen: Bool

    var body: some View {
        HStack {
            let routeText = isEyeOpen ? routeItem.route.rawValue : ""
            if let doseUnwrapped = routeItem.dose {
                // 30±5 mg oral
                let dose = doseUnwrapped.doseDescription(
                    units: routeItem.units,
                    isEstimate: routeItem.isEstimate,
                    standardDeviation: routeItem.estimatedDoseStandardDeviation,
                    rounded: true
                )
                (Text("\(dose) ") + Text(routeText).foregroundColor(.secondary))
                    .multilineTextAlignment(.trailing)
            } else {
                Text("Unknown dose ")  + Text(routeText).foregroundColor(.secondary)
            }
            Spacer()
            if let numDotsUnwrap = routeItem.numDots, !isHidingDosageDots {
                DotRows(numDots: numDotsUnwrap)
            }
        }.font(.subheadline)
    }
}

#Preview {
    List {
        Section {
            CumulativeDoseRow(
                substanceName: "MDMA",
                substanceColor: .pink,
                cumulativeRoutes: [
                    CumulativeRouteAndDose(
                        route: .oral,
                        numDots: 5,
                        isEstimate: false,
                        estimatedDoseStandardDeviation: nil,
                        dose: 250,
                        units: "mg"
                    ),
                    CumulativeRouteAndDose(
                        route: .insufflated,
                        numDots: 1,
                        isEstimate: true,
                        estimatedDoseStandardDeviation: 2,
                        dose: 20,
                        units: "mg"
                    ),
                ],
                isHidingDosageDots: false,
                isEyeOpen: true
            )
            CumulativeDoseRow(
                substanceName: "Amphetamine",
                substanceColor: .blue,
                cumulativeRoutes: [
                    CumulativeRouteAndDose(
                        route: .oral,
                        numDots: 3,
                        isEstimate: false,
                        estimatedDoseStandardDeviation: nil,
                        dose: 30,
                        units: "mg"
                    ),
                    CumulativeRouteAndDose(
                        route: .insufflated,
                        numDots: nil,
                        isEstimate: true,
                        estimatedDoseStandardDeviation: 5,
                        dose: nil,
                        units: "mg"
                    ),
                ],
                isHidingDosageDots: false,
                isEyeOpen: true
            )
        }
    }
}
