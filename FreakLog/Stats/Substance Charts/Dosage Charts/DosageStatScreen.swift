import SwiftUI
import Charts

struct DosageStatScreen: View {

    let substanceName: String
    let unit: String
    let substanceColor: SubstanceColor

    init(substanceName: String) {
        self.substanceName = substanceName
        // Units of the first route with dose data, PW routes first
        let pwRoutes = SubstanceRepo.shared.getSubstance(name: substanceName)?.roas.map(\.name) ?? []
        let roaDose = (pwRoutes + AdministrationRoute.allCases).lazy.compactMap { route in
            PersistenceController.shared.resolvedDose(for: substanceName, route: route)
        }.first
        if let roaUnit = roaDose?.units {
            unit = roaUnit
        } else {
            if let customSubstance = PersistenceController.shared.getCustomSubstance(name: substanceName) {
                unit = customSubstance.unitsUnwrapped
            } else {
                unit = ""
            }
        }
        // Assigning the wrapped value in init is discarded, so set the initial State instead
        _unknownDoseEstimate = State(initialValue: roaDose?.commonMin ?? 0)
        substanceColor = getColor(for: substanceName)
        _ingestions = FetchRequest(fetchRequest: PersistenceController.personalIngestionsRequest(for: substanceName))
    }

    @FetchRequest private var ingestions: FetchedResults<Ingestion>
    @State private var unknownDoseEstimate: Double
    @State private var isAverageShown = false

    enum DosageResolution: String, CaseIterable {
        case day = "D"
        case week = "W"
        case month = "M"
        case year = "Y"

        var component: Calendar.Component {
            switch self {
            case .day: .day
            case .week: .weekOfYear
            case .month: .month
            case .year: .year
            }
        }
    }

    @State private var selectedResolution = DosageResolution.week

    var body: some View {
        List {
            if ingestions.allSatisfy({ $0.pureUnits == unit }) {
                Section {
                    Picker("Resolution", selection: $selectedResolution) {
                        ForEach(DosageResolution.allCases, id: \.rawValue) { resolution in
                            Text(resolution.rawValue).tag(resolution)
                        }
                    }.pickerStyle(.segmented)

                    DosageStatChart(
                        data: dosages(per: selectedResolution.component),
                        resolution: selectedResolution,
                        substanceName: substanceName,
                        substanceColor: substanceColor,
                        unit: unit,
                        isAverageShown: isAverageShown
                    )
                }.listRowSeparator(.hidden)

                Section {
                    Toggle("Show Average", isOn: $isAverageShown).tint(.accentColor)
                }

                if ingestions.contains(where: { $0.doseUnwrapped == nil }) {
                    Section("Estimate unknown doses as") {
                        HStack  {
                            TextField(
                                "Unknown dose estimate",
                                value: $unknownDoseEstimate,
                                format: .number).keyboardType(.decimalPad)
                            Text(unit)
                        }
                    }
                }
            } else {
                Section {
                    let name = PersistenceController.shared.displayName(for: substanceName)
                    Text(
                        "Not all your ingestions of \(name) are using \(unit) as their pure unit. "
                            + "It's therefore not possible to sum those doses together to show a graph."
                    )
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(PersistenceController.shared.displayName(for: substanceName))
    }

    // Total dose per calendar period, with unknown doses counted as the estimate
    private func dosages(per component: Calendar.Component) -> [DosagePoint] {
        let grouped = Dictionary(grouping: ingestions) { ing in
            Calendar.current.dateInterval(of: component, for: ing.timeUnwrapped)?.start ?? ing.timeUnwrapped
        }
        return grouped.map { (date, ingestions) in
            let totalDose = ingestions.map { $0.pureSubstanceDose ?? unknownDoseEstimate }.reduce(0, +)
            return DosagePoint(date: date, dosage: totalDose)
        }.sorted { $0.date < $1.date }
    }
}

#Preview {
    DosageStatScreen(substanceName: "MDMA")
}
