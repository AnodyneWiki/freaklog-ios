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
    @AppStorage(AdministrationSiteNameStyle.preferenceKey) private var siteNameStyle = AdministrationSiteNameStyle.simple
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
            "\(ingestion.substanceDisplayName), \(customUnit.nameUnwrapped)"
        } else {
            ingestion.substanceDisplayName
        }
    }

    var rowContent: some View {
        HStack {
            ColorRectangle(color: substanceColor.swiftUIColor)
            VStack(alignment: .leading) {
                HStack {
                    timeText.font(.caption)
                    Spacer()
                    if ingestion.isHiddenFromTimeline {
                        Label("Hidden from Timeline", systemImage: "eye.slash")
                            .labelStyle(.iconOnly)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let location = ingestion.location {
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
        Text(" " + routeDescription()).foregroundColor(.secondary)
    }

    private func routeDescription(capitalized: Bool = false) -> String {
        guard isEyeOpen else { return "" }
        let route = ingestion.administrationRouteUnwrapped
        let routeText = capitalized ? route.rawValue.localizedCapitalized : route.rawValue
        let site = siteNameStyle.label(for: ingestion.administrationSiteUnwrapped, route: route)
        return site.isEmpty ? routeText : "\(routeText) (\(site))"
    }

    private var doseRow: some View {
        HStack {
            VStack(alignment: .leading) {
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
                        Text(routeDescription(capitalized: true)).foregroundColor(.secondary)
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

// Swiping an ingestion from the leading edge opens its substance's info
struct SubstanceInfoSwipeAction: ViewModifier {
    let substanceName: String

    func body(content: Content) -> some View {
        content.swipeActions(edge: .leading) {
            if let destination = Navigator.substanceInfoDestination(for: substanceName) {
                Button {
                    Navigator.shared.openInCurrentTab(destination)
                } label: {
                    Label("Substance Info", systemImage: "info.circle")
                }
                .tint(.accentColor)
            }
        }
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
