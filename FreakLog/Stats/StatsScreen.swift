import Charts
import Combine
import CoreData
import SwiftUI

struct StatsScreen: View {
    @AppStorage(PersistenceController.isEyeOpenKey2) private var isEyeOpen = false
    @AppStorage(StatsPreferences.periodKey) private var period: StatsPeriod = .last12Months
    @State private var showsAllSubstances = false
    @State private var substanceOrder = StatsSubstanceOrder.count
    @AppStorage(StatsPreferences.pinnedViewsKey) private var pinnedStatsData = Data()
    @FetchRequest(fetchRequest: PersistenceController.substanceCompanionsRequest())
    private var substanceCompanions: FetchedResults<SubstanceCompanion>

    var body: some View {
        StatsJournal { entries, tags in
            let selection = StatsSelection(period: period)
            let records = StatsRecords(entries: entries, selection: selection, tags: tags)
            let pins = StatsPreferences.decode(pinnedStatsData)

            List {
                Section {
                    Picker("Period", selection: $period) {
                        ForEach(StatsPeriod.allCases.filter { $0 != .custom }, id: \.self) { period in
                            Text(period.title).tag(period)
                        }
                    }

                    ingestionOverview(records: records, selection: selection)
                    LabeledContent("Experiences", value: records.experiences.count.formatted())
                    LabeledContent("Days Logged", value: records.daysLogged.formatted())
                } header: {
                    Text("Summary")
                }

                let counts = Dictionary(grouping: records.entries, by: \.substanceNameUnwrapped).mapValues(\.count)
                let ranked = counts.keys.sorted {
                    substanceOrder.precedes(
                        count: counts[$0, default: 0], name: PersistenceController.shared.displayName(for: $0),
                        otherCount: counts[$1, default: 0], otherName: PersistenceController.shared.displayName(for: $1)
                    )
                }
                if !ranked.isEmpty {
                    let highestCount = counts.values.max() ?? 0
                    Section {
                        ForEach(ranked.prefix(showsAllSubstances ? ranked.count : 4), id: \.self) { name in
                            NavigationLink {
                                StatsDetailScreen(metric: .ingestions, selection: selection.forSubstance(name))
                            } label: {
                                StatsComparisonRow(
                                    title: PersistenceController.shared.displayName(for: name),
                                    count: counts[name, default: 0], highestCount: highestCount,
                                    color: colors[name] ?? .accentColor
                                )
                            }
                        }
                        if ranked.count > 4 {
                            Button(showsAllSubstances ? "Show Fewer" : "Show All \(ranked.count) Substances") {
                                withAnimation { showsAllSubstances.toggle() }
                            }
                        }
                    } header: {
                        StatsSubstanceSortHeader(title: "Ingestions by Substance", order: $substanceOrder)
                    }
                }

                if !pins.isEmpty {
                    Section("Pinned Views") {
                        ForEach(pins) { pin in
                            NavigationLink {
                                StatsDetailScreen(metric: pin.metric, selection: pin.selection)
                            } label: {
                                Label(pin.name, systemImage: "pin")
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    unpin(pin, pins: pins)
                                } label: {
                                    Label("Unpin", systemImage: "pin.slash")
                                }
                            }
                        }
                    }
                }

                if isEyeOpen {
                    toleranceSection(entries: entries)
                }
            }
            .navigationTitle("Your Stats")
        }
    }

    private var colors: [String: Color] {
        Dictionary(substanceCompanions.map { ($0.substanceNameUnwrapped, $0.color.swiftUIColor) },
                   uniquingKeysWith: { first, _ in first })
    }

    private func ingestionOverview(records: StatsRecords, selection: StatsSelection) -> some View {
        let contributions = records.ingestionContributions
        let buckets = records.buckets(for: .ingestions)
        return NavigationLink {
            StatsDetailScreen(metric: .ingestions, selection: selection)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Label("Ingestions", systemImage: "list.bullet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text(records.entries.count, format: .number)
                    .font(.title2.weight(.semibold).monospacedDigit())
                if let first = buckets.first, let last = buckets.last {
                    let start = records.range.start == .distantPast ? first.interval.start : min(first.interval.start, records.range.start)
                    let end = max(last.interval.end, records.range.end)
                    Chart(contributions) { item in
                        BarMark(x: .value("Period", item.id.date, unit: records.bucketComponent),
                                y: .value("Count", item.count))
                            .foregroundStyle(by: .value("Substance", item.id.substance))
                    }
                    .chartXScale(domain: start...end)
                    .chartForegroundStyleScale(mapping: { colors[$0] ?? Color.accentColor })
                    .chartLegend(.hidden)
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 54)
                    .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func toleranceSection(entries: [Ingestion]) -> some View {
        let now = Date.now
        let calendar = Calendar.current
        let from = calendar.date(byAdding: .day, value: -90, to: calendar.startOfDay(for: now)) ?? now
        let days = entries.compactMap { entry -> SubstanceAndDay? in
            guard entry.isMine, let time = entry.time, from <= time, time <= now else { return nil }
            return SubstanceAndDay(substanceName: entry.substanceNameUnwrapped, day: time)
        }
        let chart = ExperienceLogic.chartData(for: days, substanceCompanions: Array(substanceCompanions))
        Section {
            NavigationLink(value: GlobalNavigationDestination.toleranceChart) {
                ToleranceChartOverView(toleranceWindows: chart.toleranceWindows)
            }
        } header: {
            Text("Tolerance")
        } footer: {
            if !chart.namesOfSubstancesWithMissingTolerance.isEmpty {
                Text("Excluding ") + Text(chart.namesOfSubstancesWithMissingTolerance, format: .list(type: .and))
            }
        }
    }

    private func unpin(_ pin: PinnedStatsView, pins: [PinnedStatsView]) {
        if let data = try? JSONEncoder().encode(pins.filter { $0.id != pin.id }) {
            pinnedStatsData = data
        }
    }
}

enum StatsSubstanceOrder: String, CaseIterable, Identifiable {
    case count, name

    var id: Self { self }
    var title: LocalizedStringKey { self == .count ? "Most Logged" : "Name" }

    func precedes(count: Int, name: String, otherCount: Int, otherName: String) -> Bool {
        if self == .count && count != otherCount { return count > otherCount }
        return name.localizedStandardCompare(otherName) == .orderedAscending
    }
}

struct StatsSubstanceSortHeader: View {
    let title: LocalizedStringKey
    @Binding var order: StatsSubstanceOrder

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Menu {
                Picker("Sort By", selection: $order) {
                    ForEach(StatsSubstanceOrder.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
            } label: {
                Label(order.title, systemImage: "chevron.up.chevron.down")
            }
            .textCase(nil)
            .accessibilityLabel("Sort")
            .accessibilityValue(Text(order.title))
        }
    }
}

struct StatsComparisonRow: View {
    let title: String
    let count: Int
    let highestCount: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent {
                Text(count, format: .number).monospacedDigit()
            } label: {
                Text(title)
            }
            if highestCount > 0 {
                GeometryReader { geometry in
                    Capsule()
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(count) / CGFloat(highestCount))
                }
                .frame(height: 9)
                .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

enum StatsPreferences {
    static let periodKey = "statsSummaryPeriod"
    static let pinnedViewsKey = "pinnedStatsViews"

    static func decode(_ data: Data) -> [PinnedStatsView] {
        (try? JSONDecoder().decode([PinnedStatsView].self, from: data)) ?? []
    }
}

// Observe the same context on every Stats screen. Updating an existing object can change every
// total while leaving the fetch count unchanged. This also handles changes merged from a save context.
struct StatsJournal<Content: View>: View {
    @FetchRequest(fetchRequest: PersistenceController.ingestionsRequest())
    private var ingestions: FetchedResults<Ingestion>
    @Environment(\.managedObjectContext) private var context
    @State private var revision: UInt = 0

    @ViewBuilder let content: ([Ingestion], [String: PersonalSubstanceTags]) -> Content

    var body: some View {
        let _ = revision
        let entries = Array(ingestions)
        let substances = Set(entries.map(\.substanceNameUnwrapped))
        let tags = Dictionary(uniqueKeysWithValues: substances.map { substance in
            (substance, PersistenceController.shared.personalTags(for: substance))
        })

        content(entries, tags)
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)) { notification in
                if Self.affectsStats(notification) {
                    revision &+= 1
                }
            }
    }

    static func affectsStats(_ notification: Notification) -> Bool {
        guard let changes = notification.userInfo else { return false }
        if changes[NSInvalidatedAllObjectsKey] != nil { return true }
        let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey, NSRefreshedObjectsKey, NSInvalidatedObjectsKey]
        return keys.contains { key in
            let objects = changes[key] as? Set<NSManagedObject> ?? []
            return objects.contains { object in
                object is Ingestion || object is Experience || object is SubstanceCompanion || object is SubstanceOverride || object is CustomUnit
            }
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

#Preview {
    NavigationStack {
        StatsScreen()
            .environment(\.managedObjectContext, PersistenceController.shared.viewContext)
    }
}
