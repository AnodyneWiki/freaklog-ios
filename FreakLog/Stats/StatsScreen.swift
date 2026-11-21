import Charts
import SwiftUI

struct StatsScreen: View {
    @FetchRequest(fetchRequest: PersistenceController.personalIngestionsRequest())
    var ingestions: FetchedResults<Ingestion>

    @FetchRequest(fetchRequest: PersistenceController.experiencesRequest(prefetchingIngestions: true))
    var experiences: FetchedResults<Experience>

    @FetchRequest(fetchRequest: PersistenceController.substanceCompanionsRequest())
    var substanceCompanions: FetchedResults<SubstanceCompanion>

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
        // Chart color lookups happen per mark, so resolve colors once instead of fetching per call
        let colors = Dictionary(
            substanceCompanions.map { ($0.substanceNameUnwrapped, $0.color.swiftUIColor) },
            uniquingKeysWith: { first, _ in first }
        )
        let ingestionEntries = ingestions.map { ingestion in
            WeightedSubstanceDate(substanceName: ingestion.substanceNameUnwrapped, date: ingestion.timeUnwrapped, weight: 1)
        }
        // One entry per distinct substance in an experience, weighted so each experience adds up to 1
        let experienceEntries = experiences.flatMap { experience in
            let date = experience.sortDateUnwrapped
            let names = experience.myIngestionsSorted.map(\.substanceNameUnwrapped).uniqued()
            return names.map { WeightedSubstanceDate(substanceName: $0, date: date, weight: 1 / Double(names.count)) }
        }
        ingestionData = Self.experienceData(from: ingestionEntries, colors: colors)
        experienceData = Self.experienceData(from: experienceEntries, colors: colors)
        substanceData = SubstanceData(
            last30Days: Self.substanceCounts(of: experienceEntries, where: Self.isWithinLast30Days),
            last12Months: Self.substanceCounts(of: experienceEntries, where: Self.isWithinLast12Months),
            years: Self.substanceCounts(of: experienceEntries, where: { _ in true }),
            colors: colors
        )
        let ingestionsLast90Days = ingestions.prefix { ing in
            Calendar.current.numberOfDaysBetween(ing.timeUnwrapped, and: Date()) <= 90
        }
        let substanceDays = ingestionsLast90Days.map { ing in
            SubstanceAndDay(substanceName: ing.substanceNameUnwrapped, day: ing.timeUnwrapped)
        }
        let chartData = ExperienceLogic.chartData(for: Array(substanceDays), substanceCompanions: Array(substanceCompanions))
        toleranceWindows = chartData.toleranceWindows
        substancesInIngestionsButNotToleranceChart = chartData.namesOfSubstancesWithMissingTolerance
    }

    private struct WeightedSubstanceDate {
        let substanceName: String
        let date: Date
        let weight: Double
    }

    private struct PeriodKey: Hashable {
        let substanceName: String
        let period: DateComponents
    }

    private static func isWithinLast30Days(_ date: Date) -> Bool {
        Calendar.current.numberOfDaysBetween(date, and: Date()) <= 30
    }

    private static func isWithinLast12Months(_ date: Date) -> Bool {
        Calendar.current.numberOfMonthsBetween(date, and: Date()) <= 12
    }

    private static func experienceData(from entries: [WeightedSubstanceDate], colors: [String: Color]) -> ExperienceData {
        ExperienceData(
            last30Days: counts(of: entries, in: .last30Days, where: isWithinLast30Days),
            last12Months: counts(of: entries, in: .last12Months, where: isWithinLast12Months),
            years: counts(of: entries, in: .years, where: { _ in true }),
            colors: colors
        )
    }

    // Sums entry weights per substance and calendar period
    private static func counts(
        of entries: [WeightedSubstanceDate],
        in timeRange: TimeRange,
        where isIncluded: (Date) -> Bool
    ) -> [SubstancePeriodCount] {
        let calendar = Calendar.current
        return Dictionary(grouping: entries.filter { isIncluded($0.date) }) { entry in
            let period = calendar.dateComponents(timeRange.periodComponents, from: entry.date)
            return PeriodKey(substanceName: entry.substanceName, period: period)
        }.compactMap { _, group in
            guard let first = group.first else { return nil }
            let count = group.map(\.weight).reduce(0, +)
            return SubstancePeriodCount(date: first.date, substanceName: first.substanceName, experienceCount: count)
        }
    }

    // Number of experiences each substance was part of, most first
    private static func substanceCounts(of experienceEntries: [WeightedSubstanceDate], where isIncluded: (Date) -> Bool) -> [SubstanceCount] {
        Dictionary(grouping: experienceEntries.filter { isIncluded($0.date) }, by: \.substanceName)
            .map { SubstanceCount(substanceName: $0.key, experienceCount: $0.value.count) }
            .sorted { $0.experienceCount > $1.experienceCount }
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
