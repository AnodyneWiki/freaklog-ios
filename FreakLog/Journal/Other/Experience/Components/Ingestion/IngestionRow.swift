import SwiftUI

struct IngestionRow<Content: View>: View {
    @ObservedObject var ingestion: Ingestion
    let isEyeOpen: Bool
    let isHidingDosageDots: Bool
    @ViewBuilder let timeText: Content

    var body: some View {
        IngestionRowContent(
            ingestion: ingestion,
            substanceColor: ingestion.substanceColor,
            isEyeOpen: isEyeOpen,
            isHidingDosageDots: isHidingDosageDots,
            timeText: {timeText}
        ).foregroundColor(.primary) // to override the button styles
    }
}

private struct IngestionRowContent<Content: View>: View {
    @ObservedObject var ingestion: Ingestion
    let substanceColor: SubstanceColor
    let isEyeOpen: Bool
    let isHidingDosageDots: Bool
    @ViewBuilder let timeText: Content

    var body: some View {
        rowContent.alignmentGuide(.listRowSeparatorLeading) { dimension in
            dimension[.leading]
        }
    }

    private var title: String {
        if let customUnit = ingestion.customUnit {
            "\(ingestion.substanceNameUnwrapped), \(customUnit.nameUnwrapped)"
        } else {
            ingestion.substanceNameUnwrapped
        }
    }

    var rowContent: some View {
        HStack {
            ColorRectangle(color: substanceColor.swiftUIColor)
            VStack(alignment: .leading) {
                HStack {
                    timeText.font(.caption)
                    Spacer()
                    if let location = ingestion.locationUnwrapped {
                        Group {
                            Text(Image(systemName: "mappin")) + Text(" ") + Text(location.nameUnwrapped)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                doseRow
                Group {
                    if !ingestion.noteUnwrapped.isEmpty {
                        Text(ingestion.noteUnwrapped)
                    }
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
        }
    }

    private var routeTextWithSpace: Text {
        let routeText = isEyeOpen ? ingestion.administrationRouteUnwrapped.rawValue : ""
        let administrationSiteText = isEyeOpen && !ingestion.administrationSiteUnwrapped.isEmpty ? " (\(ingestion.administrationSiteUnwrapped.lowercased()))" : ""
        return Text(" " + routeText + administrationSiteText).foregroundColor(.secondary)
    }

    private var doseRow: some View {
        HStack {
            VStack(alignment: .leading) {
                let routeText = isEyeOpen ? ingestion.administrationRouteUnwrapped.rawValue : ""
                if let customUnitDose = ingestion.customUnitDose {
                    if let calculatedDoseDescription = customUnitDose.calculatedDoseDescription {
                        Text(customUnitDose.doseDescription) + Text(" = \(calculatedDoseDescription)").foregroundColor(.secondary) + routeTextWithSpace
                    } else {
                        Text(customUnitDose.doseDescription) + Text(" = unknown dose").foregroundColor(.secondary) + routeTextWithSpace
                    }
                } else { // not custom unit
                    if let doseUnwrapped = ingestion.doseUnwrapped {
                        // 20±5 mg insufflated
                        Text(doseUnwrapped.doseDescription(
                            units: ingestion.unitsUnwrapped,
                            isEstimate: ingestion.isEstimate,
                            standardDeviation: ingestion.estimatedDoseStandardDeviationUnwrapped
                        )) + routeTextWithSpace
                    } else {
                        // Insufflated
                        Text(routeText.localizedCapitalized).foregroundColor(.secondary)
                    }
                }
                
            }
            Spacer()
            if !isHidingDosageDots, let numDotsUnwrap = ingestion.numberOfDots {
                DotRows(numDots: numDotsUnwrap)
            }
        }
        .font(.subheadline)
        .multilineTextAlignment(.trailing)
    }
}

#Preview {
    List {
        Section {
            IngestionRowContent(
                ingestion: Ingestion.knownDosePreviewSample,
                substanceColor: .pink,
                isEyeOpen: true,
                isHidingDosageDots: false,
                timeText: {
                    Text("Sat 13:44")
                }
            )
            IngestionRowContent(
                ingestion: Ingestion.estimatedDosePreviewSample,
                substanceColor: .blue,
                isEyeOpen: true,
                isHidingDosageDots: false,
                timeText: {
                    Text("Sat 13:44")
                }
            )
            IngestionRowContent(
                ingestion: Ingestion.unknownDosePreviewSample,
                substanceColor: .blue,
                isEyeOpen: true,
                isHidingDosageDots: false,
                timeText: {
                    Text("Sat 13:44")
                }            )
            IngestionRowContent(
                ingestion: Ingestion.notePreviewSample,
                substanceColor: .blue,
                isEyeOpen: true,
                isHidingDosageDots: false,
                timeText: {
                    Text("Sat 13:44")
                }
            )
            IngestionRowContent(
                ingestion: Ingestion.customSubstancePreviewSample,
                substanceColor: .purple,
                isEyeOpen: true,
                isHidingDosageDots: false,
                timeText: {
                    Text("Sat 13:44")
                }            )
            IngestionRowContent(
                ingestion: Ingestion.customUnitPreviewSample,
                substanceColor: .orange,
                isEyeOpen: true,
                isHidingDosageDots: false,
                timeText: {
                    Text("Sat 13:44")
                }
            )
            IngestionRowContent(
                ingestion: Ingestion.customUnitUnknownDosePreviewSample,
                substanceColor: .orange,
                isEyeOpen: true,
                isHidingDosageDots: false,
                timeText: {
                    Text("Sat 13:44")
                }
            )
            IngestionRowContent(
                ingestion: Ingestion.estimatedCustomUnitPreviewSample,
                substanceColor: .orange,
                isEyeOpen: true,
                isHidingDosageDots: false,
                timeText: {
                    Text("Sat 13:44")
                }
            )
            IngestionRowContent(
                ingestion: Ingestion.estimatedQuantitativelyCustomUnitPreviewSample,
                substanceColor: .orange,
                isEyeOpen: true,
                isHidingDosageDots: false,
                timeText: {
                    Text("Sat 13:44")
                }
            )
            IngestionRowContent(
                ingestion: Ingestion.everythingEstimatedQuantitativelyPreviewSample,
                substanceColor: .orange,
                isEyeOpen: true,
                isHidingDosageDots: false,
                timeText: {
                    Text("Sat 13:44")
                }
            )
        }
    }
}
