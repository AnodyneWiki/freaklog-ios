import Charts
import SwiftUI

struct StatsScreen: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Ingestion.time, ascending: false)],
        predicate: NSPredicate(format: "consumerName=nil OR consumerName=''")
    ) var ingestions: FetchedResults<Ingestion>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Experience.sortDate, ascending: false)]
    ) var experiences: FetchedResults<Experience>

    @FetchRequest(
        sortDescriptors: []
    ) var substanceCompanions: FetchedResults<SubstanceCompanion>

    @State private var experienceData: ExperienceData?
    @State private var ingestionData: ExperienceData?
    @State private var substanceData: SubstanceData?
    @State private var toleranceWindows: [ToleranceWindow] = []
    @State private var substancesInIngestionsButNotToleranceChart: [String] = []

    @AppStorage(PersistenceController.isEyeOpenKey2) var isEyeOpen: Bool = false

    var body: some View {
        Group {
            if let experienceData, let ingestionData, let substanceData {
                StatsScreenContent(
                    experienceData: experienceData,
                    ingestionData: ingestionData,
                    substanceData: substanceData,
                    toleranceWindows: toleranceWindows,
                    substancesInIngestionsButNotChart: substancesInIngestionsButNotToleranceChart,
                    isEyeOpen: isEyeOpen
                )
            } else {
                ProgressView().task {
                    calculateStats()
                }
            }
        }.onChange(of: ingestions.count) { _ in
            calculateStats()
        }
    }

    private func calculateStats() {
        ingestionData = buildIngestionData()
        experienceData = ExperienceData(
            last30Days: getExperienceCountsLast30Days(),
            last12Months: getExperienceCountsLast12Months(),
            years: getExperienceCountsYears(),
            colorMapping: { substanceName in
                getColor(for: substanceName).swiftUIColor
            }
        )
        substanceData = SubstanceData(
            last30Days: getSortedSubstanceCountsLast30Days(),
            last12Months: getSortedSubstanceCountsLast12Months(),
            years: getSortedSubstanceCountsYears(),
            colorMapping: { substanceName in
                getColor(for: substanceName).swiftUIColor
            }
        )
        let ingestionsLast90Days = ingestions.prefix { ing in
            Calendar.current.numberOfDaysBetween(ing.timeUnwrapped, and: Date()) <= 90
        }
        let substanceDays = ingestionsLast90Days.map { ing in
            SubstanceAndDay(substanceName: ing.substanceNameUnwrapped, day: ing.timeUnwrapped)
        }
        toleranceWindows = ToleranceChartCalculator.getToleranceWindows(
            from: substanceDays,
            substanceCompanions: Array(substanceCompanions)
        )
        let substancesInIngestions = Set(ingestionsLast90Days.map { $0.substanceNameUnwrapped })
        let substancesInToleranceWindows = Set(toleranceWindows.map { $0.substanceName })
        let substancesWithoutToleranceWindows = substancesInIngestions.subtracting(substancesInToleranceWindows)
        substancesInIngestionsButNotToleranceChart = Array(substancesWithoutToleranceWindows)
    }


    private func buildIngestionData() -> ExperienceData {
        ExperienceData(
            last30Days: getIngestionCountsLast30Days(),
            last12Months: getIngestionCountsLast12Months(),
            years: getIngestionCountsYears(),
            colorMapping: { substanceName in
                getColor(for: substanceName).swiftUIColor
            }
        )
    }

    private func getIngestionCountsLast30Days() -> [SubstanceExperienceCountForDay] {
        let last30Days = ingestions.prefix { ing in
            Calendar.current.numberOfDaysBetween(ing.timeUnwrapped, and: Date()) <= 30
        }
        return Dictionary(grouping: last30Days) { ing in
            var key = ing.substanceNameUnwrapped
            let c = Calendar.current.dateComponents([.year, .month, .day], from: ing.timeUnwrapped)
            if let y = c.year, let m = c.month, let d = c.day { key += "\(y)\(m)\(d)" }
            return key
        }.compactMap { (_, ings) in
            guard let first = ings.first else { return nil }
            return SubstanceExperienceCountForDay(
                day: first.timeUnwrapped,
                substanceName: first.substanceNameUnwrapped,
                experienceCount: Double(ings.count)
            )
        }
    }

    private func getIngestionCountsLast12Months() -> [SubstanceExperienceCountForMonth] {
        let last12Months = ingestions.prefix { ing in
            Calendar.current.numberOfMonthsBetween(ing.timeUnwrapped, and: Date()) <= 12
        }
        return Dictionary(grouping: last12Months) { ing in
            var key = ing.substanceNameUnwrapped
            let c = Calendar.current.dateComponents([.year, .month], from: ing.timeUnwrapped)
            if let y = c.year, let m = c.month { key += "\(y)\(m)" }
            return key
        }.compactMap { (_, ings) in
            guard let first = ings.first else { return nil }
            return SubstanceExperienceCountForMonth(
                month: first.timeUnwrapped,
                substanceName: first.substanceNameUnwrapped,
                experienceCount: Double(ings.count)
            )
        }
    }

    private func getIngestionCountsYears() -> [SubstanceExperienceCountForYear] {
        Dictionary(grouping: ingestions) { ing in
            var key = ing.substanceNameUnwrapped
            let c = Calendar.current.dateComponents([.year], from: ing.timeUnwrapped)
            if let y = c.year { key += "\(y)" }
            return key
        }.compactMap { (_, ings) in
            guard let first = ings.first else { return nil }
            return SubstanceExperienceCountForYear(
                year: first.timeUnwrapped,
                substanceName: first.substanceNameUnwrapped,
                experienceCount: Double(ings.count)
            )
        }
    }

    private func getSortedSubstanceCountsLast30Days() -> [SubstanceCount] {
        let last30Days = experiences.prefix { exp in
            Calendar.current.numberOfDaysBetween(exp.sortDateUnwrapped, and: Date()) <= 30
        }
        return getSortedSubstanceCounts(for: last30Days)
    }

    private func getSortedSubstanceCountsLast12Months() -> [SubstanceCount] {
        let last12Months = experiences.prefix { exp in
            Calendar.current.numberOfMonthsBetween(exp.sortDateUnwrapped, and: Date()) <= 12
        }
        return getSortedSubstanceCounts(for: last12Months)
    }

    private func getSortedSubstanceCountsYears() -> [SubstanceCount] {
        return getSortedSubstanceCounts(for: experiences)
    }

    private func getSortedSubstanceCounts(for experiences: any Sequence<Experience>) -> [SubstanceCount] {
        let substanceNameOccurances = experiences.flatMap { experience in
            experience.myIngestionsSorted.map { ingestion in
                ingestion.substanceNameUnwrapped
            }.uniqued()
        }
        var countDict: [String: Int] = [:]
        for substanceName in substanceNameOccurances {
            countDict[substanceName, default: 0] += 1
        }
        return countDict.map { (substanceName: String, count: Int) in
            SubstanceCount(
                substanceName: substanceName,
                experienceCount: count
            )
        }.sorted { count1, count2 in
            count1.experienceCount > count2.experienceCount
        }
    }

    private func getExperienceCountsLast30Days() -> [SubstanceExperienceCountForDay] {
        let experiencesLast30Days = experiences.prefix { experience in
            Calendar.current.numberOfDaysBetween(experience.sortDateUnwrapped, and: Date()) <= 30
        }
        let ungroupedResult = experiencesLast30Days.flatMap { experience in
            let distinctSubstanceNames = experience.myIngestionsSorted.map { $0.substanceNameUnwrapped }.uniqued()
            return distinctSubstanceNames.map { substanceName in
                SubstanceExperienceCountForDay(
                    day: experience.sortDateUnwrapped,
                    substanceName: substanceName,
                    experienceCount: 1 / Double(distinctSubstanceNames.count)
                )
            }
        }
        return Dictionary(grouping: ungroupedResult) { result in
            let components = Calendar.current.dateComponents([.year, .month, .day], from: result.day)
            var substanceYearMonthDay = result.substanceName
            if let year = components.year, let month = components.month, let day = components.day {
                substanceYearMonthDay += String(year) + String(month) + String(day)
            }
            return substanceYearMonthDay
        }.compactMap { (_: _, matchesForSameDay: [SubstanceExperienceCountForDay]) in
            guard let first = matchesForSameDay.first else { return nil }
            let experienceCount = matchesForSameDay.map { $0.experienceCount }.reduce(0, +)
            return SubstanceExperienceCountForDay(
                day: first.day,
                substanceName: first.substanceName,
                experienceCount: experienceCount
            )
        }
    }

    private func getExperienceCountsLast12Months() -> [SubstanceExperienceCountForMonth] {
        let experiencesLast12Months = experiences.prefix { experience in
            Calendar.current.numberOfMonthsBetween(experience.sortDateUnwrapped, and: Date()) <= 12
        }
        let ungroupedResult = experiencesLast12Months.flatMap { experience in
            let distinctSubstanceNames = experience.myIngestionsSorted.map { $0.substanceNameUnwrapped }.uniqued()
            return distinctSubstanceNames.map { substanceName in
                SubstanceExperienceCountForMonth(
                    month: experience.sortDateUnwrapped,
                    substanceName: substanceName,
                    experienceCount: 1 / Double(distinctSubstanceNames.count)
                )
            }
        }
        return Dictionary(grouping: ungroupedResult) { result in
            let components = Calendar.current.dateComponents([.year, .month], from: result.month)
            var substanceYearMonth = result.substanceName
            if let year = components.year, let month = components.month {
                substanceYearMonth += String(year) + String(month)
            }
            return substanceYearMonth
        }.compactMap { (_: _, matchesForSameMonth: [SubstanceExperienceCountForMonth]) in
            guard let first = matchesForSameMonth.first else { return nil }
            let experienceCount = matchesForSameMonth.map { $0.experienceCount }.reduce(0, +)
            return SubstanceExperienceCountForMonth(
                month: first.month,
                substanceName: first.substanceName,
                experienceCount: experienceCount
            )
        }
    }

    private func getExperienceCountsYears() -> [SubstanceExperienceCountForYear] {
        let ungroupedResult = experiences.flatMap { experience in
            let distinctSubstanceNames = experience.myIngestionsSorted.map { $0.substanceNameUnwrapped }.uniqued()
            return distinctSubstanceNames.map { substanceName in
                SubstanceExperienceCountForYear(
                    year: experience.sortDateUnwrapped,
                    substanceName: substanceName,
                    experienceCount: 1 / Double(distinctSubstanceNames.count)
                )
            }
        }
        return Dictionary(grouping: ungroupedResult) { result in
            let components = Calendar.current.dateComponents([.year], from: result.year)
            var substanceYear = result.substanceName
            if let year = components.year {
                substanceYear += String(year)
            }
            return substanceYear
        }.compactMap { (_: _, matchesForSameYear: [SubstanceExperienceCountForYear]) in
            guard let first = matchesForSameYear.first else { return nil }
            let experienceCount = matchesForSameYear.map { $0.experienceCount }.reduce(0, +)
            return SubstanceExperienceCountForYear(
                year: first.year,
                substanceName: first.substanceName,
                experienceCount: experienceCount
            )
        }
    }
}

extension Calendar {
    // swiftlint:disable identifier_name
    func numberOfDaysBetween(_ from: Date, and to: Date) -> Int {
        let fromDate = startOfDay(for: from)
        let toDate = startOfDay(for: to)
        let numberOfDays = dateComponents([.day], from: fromDate, to: toDate)
        return numberOfDays.day!
    }

    func numberOfMonthsBetween(_ from: Date, and to: Date) -> Int {
        let fromDate = startOfDay(for: from)
        let toDate = startOfDay(for: to)
        let numberOfMonths = dateComponents([.month], from: fromDate, to: toDate)
        return numberOfMonths.month!
    }
    // swiftlint:enable identifier_name
}

struct StatsScreenContent: View {
    let experienceData: ExperienceData
    let ingestionData: ExperienceData
    let substanceData: SubstanceData
    let toleranceWindows: [ToleranceWindow]
    let substancesInIngestionsButNotChart: [String]
    let isEyeOpen: Bool

    var body: some View {
        List {
            if isEyeOpen {
                Section {
                    NavigationLink(value: GlobalNavigationDestination.toleranceChart) {
                        ToleranceChartOverView(toleranceWindows: toleranceWindows)
                    }
                } footer: {
                    if !substancesInIngestionsButNotChart.isEmpty {
                        Text("Excluding ") + Text(substancesInIngestionsButNotChart, format: .list(type: .and))
                    }
                }
            }
            Section {
                NavigationLink(
                    value: GlobalNavigationDestination.experienceDetails(
                        experienceData: experienceData,
                        ingestionData: ingestionData
                    )
                ) {
                    ExperienceOverview(experienceData: experienceData)
                }
            }
            Section {
                NavigationLink(value: GlobalNavigationDestination.substanceDetails(substanceData: substanceData)) {
                    SubstanceOverview(substanceData: substanceData)
                }
            }
        }.navigationTitle("Your Stats")
    }
}

#Preview {
    NavigationStack {
        StatsScreenContent(
            experienceData: .mock1,
            ingestionData: .mock1,
            substanceData: .mock1,
            toleranceWindows: ToleranceChartPreviewDataProvider.mock1,
            substancesInIngestionsButNotChart: ["2C-B", "DMT"],
            isEyeOpen: true
        )
    }
}
