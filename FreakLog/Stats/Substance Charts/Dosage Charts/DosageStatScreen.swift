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

                    switch selectedResolution {
                    case .day:
                        DosageStatDayChart(
                            dayDosages: dosageStat?.dayDosages ?? [],
                            substanceName: substanceName,
                            substanceColor: substanceColor,
                            unit: unit,
                            isAverageShown: isAverageShown
                        )
                    case .week:
                        DosageStatWeekChart(
                            weekDosages: dosageStat?.weekDosages ?? [],
                            substanceName: substanceName,
                            substanceColor: substanceColor,
                            unit: unit,
                            isAverageShown: isAverageShown
                        )
                    case .month:
                        DosageStatMonthChart(
                            monthDosages: dosageStat?.monthDosages ?? [],
                            substanceName: substanceName,
                            substanceColor: substanceColor,
                            unit: unit,
                            isAverageShown: isAverageShown
                        )
                    case .year:
                        DosageStatYearChart(
                            yearDosages: dosageStat?.yearDosages ?? [],
                            substanceName: substanceName,
                            substanceColor: substanceColor,
                            unit: unit,
                            isAverageShown: isAverageShown
                        )
                    }
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

    struct DoseInstance {
        let date: Date
        let dose: Double
    }

    private func updateStats() {
        doAllIngestionsHaveSameUnitEqualToSubstance = ingestions.wrappedValue.allSatisfy({ ing in
            ing.pureUnits == unit
        })
        areThereUnknownDoses = ingestions.wrappedValue.contains(where: { ing in
            ing.doseUnwrapped == nil
        })
        dosageStat = DosageStat(
            dayDosages: getDayDosages(),
            weekDosages: getWeekDosages(),
            monthDosages: getMonthDosages(),
            yearDosages: getYearDosages())
    }

    private func getDayDosages() -> [DayDosage] {
        let doseInstances = convertToDoseInstances(ingestions: ingestions.wrappedValue)
        let grouped = Dictionary(grouping: doseInstances) { instance in
            Calendar.current.startOfDay(for: instance.date)
        }
        return grouped.map { (date, instances) in
            DayDosage(day: date, dosage: instances.map(\.dose).reduce(0, +))
        }.sorted { $0.day < $1.day }
    }

    private func getWeekDosages() -> [WeekDosage] {
        let doseInstances = convertToDoseInstances(ingestions: ingestions.wrappedValue)
        let grouped = Dictionary(grouping: doseInstances) { instance in
            Calendar.current.dateInterval(of: .weekOfYear, for: instance.date)?.start ?? instance.date
        }
        return grouped.map { (date, instances) in
            WeekDosage(week: date, dosage: instances.map(\.dose).reduce(0, +))
        }.sorted { $0.week < $1.week }
    }

    private func getMonthDosages() -> [MonthDosage] {
        let doseInstances = convertToDoseInstances(ingestions: ingestions.wrappedValue)
        let grouped = Dictionary(grouping: doseInstances) { instance in
            Calendar.current.dateInterval(of: .month, for: instance.date)?.start ?? instance.date
        }
        return grouped.map { (date, instances) in
            MonthDosage(month: date, dosage: instances.map(\.dose).reduce(0, +))
        }.sorted { $0.month < $1.month }
    }

    private func getYearDosages() -> [YearDosage] {
        let doseInstances = convertToDoseInstances(ingestions: ingestions.wrappedValue)
        let grouped = Dictionary(grouping: doseInstances) { instance in
            Calendar.current.dateInterval(of: .year, for: instance.date)?.start ?? instance.date
        }
        return grouped.map { (date, instances) in
            YearDosage(year: date, dosage: instances.map(\.dose).reduce(0, +))
        }.sorted { $0.year < $1.year }
    }

    private func convertToDoseInstances(ingestions: any Collection<Ingestion>) -> [DoseInstance] {
        return ingestions.map { ing in
            DoseInstance(date: ing.timeUnwrapped, dose: ing.pureSubstanceDose ?? unknownDoseEstimate)
        }
    }
}

#Preview {
    DosageStatScreen(substanceName: "MDMA")
}
