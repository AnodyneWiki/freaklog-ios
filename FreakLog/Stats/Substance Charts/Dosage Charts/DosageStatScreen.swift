import SwiftUI
import Charts

struct DosageStatScreen: View {

    let substanceName: String
    let unit: String
    let substanceColor: SubstanceColor

    init(substanceName: String) {
        self.substanceName = substanceName
        let substance = SubstanceRepo.shared.getSubstance(name: substanceName)
        let roaDose = substance?.roas.first?.dose
        if let roaUnit = roaDose?.units {
            unit = roaUnit
        } else {
            if let customSubstance = PersistenceController.shared.getCustomSubstance(name: substanceName) {
                unit = customSubstance.unitsUnwrapped
            } else {
                unit = ""
            }
        }
        unknownDoseEstimate = roaDose?.commonMin ?? 0
        substanceColor = getColor(for: substanceName)
        self.ingestions = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Ingestion.time, ascending: false)],
            predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "consumerName=nil OR consumerName=''"),
                NSPredicate(format: "substanceName == %@", substanceName)
            ]))
    }

    private var ingestions: FetchRequest<Ingestion>
    @State private var unknownDoseEstimate = 0.0
    @State private var isAverageShown = false

    enum DosageResolution: String, CaseIterable {
        case day = "D"
        case week = "W"
        case month = "M"
        case year = "Y"
    }

    @State private var selectedResolution = DosageResolution.week

    var body: some View {
        List {
            if doAllIngestionsHaveSameUnitEqualToSubstance {
                Section {
                    Picker("Resolution", selection: $selectedResolution) {
                        ForEach(DosageResolution.allCases, id: \.rawValue) { resolution in
                            Text(resolution.rawValue).tag(resolution)
                        }
                    }.pickerStyle(.segmented)

                    DosageStatChart(
                        data: currentDosageData,
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

                if areThereUnknownDoses {
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
                    Text("Not all your ingestions of \(substanceName) are using \(unit) as their pure unit. It's therefore not possible to sum those doses together to show a graph.")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(substanceName)
        .onAppear {
            updateStats()
        }
        .onChange(of: ingestions.wrappedValue.count, perform: { _ in
            updateStats()
        })
        .onChange(of: unknownDoseEstimate) { newValue in
            updateStats()
        }
    }

    @State private var dosageStat: DosageStat?
    @State private var areThereUnknownDoses = false
    @State private var doAllIngestionsHaveSameUnitEqualToSubstance = true
    private var currentDosageData: [DosagePoint] {
        guard let stat = dosageStat else { return [] }
        switch selectedResolution {
        case .day: return stat.dayDosages
        case .week: return stat.weekDosages
        case .month: return stat.monthDosages
        case .year: return stat.yearDosages
        }
    }

    private func updateStats() {
        doAllIngestionsHaveSameUnitEqualToSubstance = ingestions.wrappedValue.allSatisfy({ ing in
            ing.pureUnits == unit
        })
        areThereUnknownDoses = ingestions.wrappedValue.contains(where: { ing in
            ing.doseUnwrapped == nil
        })
        dosageStat = DosageStat(
            dayDosages: calculateDosages(for: .day),
            weekDosages: calculateDosages(for: .weekOfYear),
            monthDosages: calculateDosages(for: .month),
            yearDosages: calculateDosages(for: .year))
    }

    private func calculateDosages(for component: Calendar.Component) -> [DosagePoint] {
        let ingestions = ingestions.wrappedValue
        let grouped = Dictionary(grouping: ingestions) { ing in
            if component == .day {
                return Calendar.current.startOfDay(for: ing.timeUnwrapped)
            } else {
                return Calendar.current.dateInterval(of: component, for: ing.timeUnwrapped)?.start ?? ing.timeUnwrapped
            }
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
