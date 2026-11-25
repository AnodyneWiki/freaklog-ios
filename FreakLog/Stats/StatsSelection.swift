import CoreData
import SwiftUI

enum StatsPeriod: String, CaseIterable, Codable {
    case last7Days
    case last30Days
    case thisMonth
    case last12Months
    case allTime
    case custom

    var title: LocalizedStringKey {
        switch self {
        case .last7Days: "Last 7 Days"
        case .last30Days: "Last 30 Days"
        case .thisMonth: "This Month"
        case .last12Months: "Last 12 Months"
        case .allTime: "All Time"
        case .custom: "Custom Dates"
        }
    }
}

enum StatsMetric: String, Codable {
    case experiences
    case ingestions
    case gaps

    var title: LocalizedStringKey {
        switch self {
        case .experiences: "Experiences"
        case .ingestions: "Ingestions"
        case .gaps: "Time Between Logs"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        if rawValue == "days" || rawValue == "amounts" {
            // Older pins now open the ingestion detail with their original filters.
            self = .ingestions
        } else if let metric = Self(rawValue: rawValue) {
            self = metric
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized stats metric.")
        }
    }
}

struct StatsSelection: Codable, Equatable {
    enum Person: Codable, Equatable, Hashable {
        case me
        case everyone
        case named(String)
    }

    var period: StatsPeriod = .last30Days
    var customStart = Calendar.current.date(byAdding: .day, value: -29, to: .now) ?? .now
    var customEnd = Date.now
    var substances: Set<String> = []
    var route: AdministrationRoute?
    var person: Person = .me
    var tags: Set<String> = []
    var matchesPrimaryTagOnly = false
    var requiredPrimaryTag: String?
    var alongside: String?
    var alongsideFilter: EntryFilter?
    var focus: Focus?

    struct Focus: Codable, Equatable {
        let interval: DateInterval
        let metric: StatsMetric
        let sourceInterval: DateInterval
        let experienceFilter: EntryFilter?
    }

    struct EntryFilter: Codable, Equatable {
        let substances: Set<String>
        let route: AdministrationRoute?
        let person: Person
        let tags: Set<String>
        let matchesPrimaryTagOnly: Bool
        let requiredPrimaryTag: String?

        func includes(_ ingestion: Ingestion, tags personalTags: PersonalSubstanceTags) -> Bool {
            if !substances.isEmpty, !substances.contains(ingestion.substanceNameUnwrapped) { return false }
            if let route, route != ingestion.administrationRouteUnwrapped { return false }
            if let requiredPrimaryTag,
               personalTags.primary.map(PersonalSubstanceTags.key) != PersonalSubstanceTags.key(requiredPrimaryTag) { return false }
            if !tags.isEmpty {
                let names = matchesPrimaryTagOnly ? [personalTags.primary].compactMap { $0 } : personalTags.names
                let keys = Set(names.map(PersonalSubstanceTags.key))
                guard tags.contains(where: { keys.contains(PersonalSubstanceTags.key($0)) }) else { return false }
            }

            return includesPerson(ingestion)
        }

        func includesPerson(_ ingestion: Ingestion) -> Bool {
            switch person {
            case .me: return ingestion.isMine
            case .everyone: return true
            case .named(let name): return ingestion.consumerNameUnwrapped == name
            }
        }
    }

    init(
        period: StatsPeriod = .last30Days,
        customStart: Date = Calendar.current.date(byAdding: .day, value: -29, to: .now) ?? .now,
        customEnd: Date = .now,
        substance: String? = nil,
        route: AdministrationRoute? = nil,
        person: Person = .me,
        tag: String? = nil
    ) {
        self.period = period
        self.customStart = customStart
        self.customEnd = customEnd
        self.substances = substance.map { [$0] } ?? []
        self.route = route
        self.person = person
        self.tags = tag.map { [$0] } ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case period, customStart, customEnd, substances, route, person, tags, matchesPrimaryTagOnly, requiredPrimaryTag
        case alongside, alongsideFilter, focus
    }

    private enum LegacyKeys: String, CodingKey {
        case substance, tag
    }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        self.init(
            period: try fields.decode(StatsPeriod.self, forKey: .period),
            customStart: try fields.decode(Date.self, forKey: .customStart),
            customEnd: try fields.decode(Date.self, forKey: .customEnd),
            substance: try legacy.decodeIfPresent(String.self, forKey: .substance),
            route: try fields.decodeIfPresent(AdministrationRoute.self, forKey: .route),
            person: try fields.decode(Person.self, forKey: .person),
            tag: try legacy.decodeIfPresent(String.self, forKey: .tag)
        )
        substances = try fields.decodeIfPresent(Set<String>.self, forKey: .substances) ?? substances
        tags = try fields.decodeIfPresent(Set<String>.self, forKey: .tags) ?? tags
        matchesPrimaryTagOnly = try fields.decodeIfPresent(Bool.self, forKey: .matchesPrimaryTagOnly) ?? false
        requiredPrimaryTag = try fields.decodeIfPresent(String.self, forKey: .requiredPrimaryTag)
        alongside = try fields.decodeIfPresent(String.self, forKey: .alongside)
        alongsideFilter = try fields.decodeIfPresent(EntryFilter.self, forKey: .alongsideFilter)
        focus = try fields.decodeIfPresent(Focus.self, forKey: .focus)
    }

    var singleSubstance: String? { substances.count == 1 ? substances.first : nil }

    func forSubstance(_ name: String) -> Self {
        var copy = self
        copy.substances = [name]
        return copy
    }

    func focused(on interval: DateInterval, metric: StatsMetric, within sourceInterval: DateInterval) -> Self {
        var copy = self
        copy.focus = Focus(
            interval: interval, metric: metric, sourceInterval: sourceInterval,
            experienceFilter: metric == .experiences ? focus?.experienceFilter ?? entryFilter : nil
        )
        return copy
    }

    var hasFilters: Bool {
        !substances.isEmpty || route != nil || !tags.isEmpty || requiredPrimaryTag != nil || person != .me
    }

    func dateRange(now: Date, calendar: Calendar = .current) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let until = now.addingTimeInterval(0.001)
        switch period {
        case .last7Days:
            return DateInterval(start: calendar.date(byAdding: .day, value: -6, to: today) ?? today, end: until)
        case .last30Days:
            return DateInterval(start: calendar.date(byAdding: .day, value: -29, to: today) ?? today, end: until)
        case .thisMonth:
            return DateInterval(start: calendar.dateInterval(of: .month, for: today)?.start ?? today, end: until)
        case .last12Months:
            return DateInterval(start: calendar.date(byAdding: .month, value: -12, to: today) ?? today, end: until)
        case .allTime:
            return DateInterval(start: .distantPast, end: .distantFuture)
        case .custom:
            let firstDay = calendar.startOfDay(for: min(customStart, customEnd, now))
            let lastDay = calendar.startOfDay(for: min(max(customStart, customEnd), now))
            let nextDay = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? until
            return DateInterval(start: firstDay, end: min(nextDay, until))
        }
    }

    func includes(_ ingestion: Ingestion, tags: PersonalSubstanceTags) -> Bool {
        entryFilter.includes(ingestion, tags: tags)
    }

    var entryFilter: EntryFilter {
        EntryFilter(
            substances: substances, route: route, person: person, tags: tags,
            matchesPrimaryTagOnly: matchesPrimaryTagOnly, requiredPrimaryTag: requiredPrimaryTag
        )
    }
}

struct StatsRecords {
    private struct Cohort: Hashable {
        let experienceID: NSManagedObjectID
        let consumer: String?

        init?(_ entry: Ingestion) {
            guard let experience = entry.experience else { return nil }
            experienceID = experience.objectID
            consumer = Ingestion.storedConsumerName(entry.consumerNameUnwrapped)
        }
    }
    struct ExperienceMatch {
        let experience: Experience
        let firstMatchingDate: Date
        let entries: [Ingestion]
    }

    struct Bucket: Identifiable {
        var id: Date { interval.start }
        let interval: DateInterval
        let count: Int
    }

    struct Contribution: Identifiable {
        struct Key: Hashable {
            let date: Date
            let substance: String
        }

        let id: Key
        let count: Int
    }

    var ingestionContributions: [Contribution] {
        var counts: [Contribution.Key: Int] = [:]
        let component = bucketComponent
        for entry in entries {
            guard let date = entry.time,
                  let start = calendar.dateInterval(of: component, for: date)?.start else { continue }
            counts[.init(date: start, substance: entry.substanceNameUnwrapped), default: 0] += 1
        }
        return counts.map { Contribution(id: $0.key, count: $0.value) }.sorted {
            ($0.id.date, $0.id.substance) < ($1.id.date, $1.id.substance)
        }
    }

    struct Amount: Identifiable {
        struct Key: Hashable {
            let substance: String
            let unit: String
            let customUnitID: NSManagedObjectID?
        }

        var id: Key { key }
        let key: Key
        let total: Double
        let count: Int
        let average: Double
        let median: Double
        let minimum: Double
        let maximum: Double
        let customUnitName: String?
    }

    struct Gap: Identifiable {
        var id: NSManagedObjectID { newer.objectID }
        let older: Ingestion
        let newer: Ingestion
        let duration: TimeInterval
    }

    let range: DateInterval
    let entries: [Ingestion]
    let experiences: [ExperienceMatch]
    let calendar: Calendar

    init(
        entries: [Ingestion],
        selection: StatsSelection,
        now: Date = .now,
        calendar: Calendar = .current,
        tags: [String: PersonalSubstanceTags] = [:]
    ) {
        let range = selection.focus?.sourceInterval ?? selection.dateRange(now: now, calendar: calendar)
        let datedEntries = entries.filter { ingestion in
            guard !ingestion.isUnconfirmed, let time = ingestion.time else { return false }
            return range.start <= time && time < range.end
        }
        func matches(_ entry: Ingestion, filter: StatsSelection.EntryFilter) -> Bool {
            filter.includes(entry, tags: tags[entry.substanceNameUnwrapped, default: PersonalSubstanceTags()])
        }
        let filter = selection.entryFilter
        var alongsideCohorts: Set<Cohort>?
        if let anchor = selection.alongside {
            let anchors = datedEntries.filter { entry in
                guard entry.substanceNameUnwrapped == anchor else { return false }
                if let focus = selection.focus, focus.metric == .ingestions,
                   let time = entry.time, !(focus.interval.start <= time && time < focus.interval.end) {
                    return false
                }
                if let alongsideFilter = selection.alongsideFilter {
                    return matches(entry, filter: alongsideFilter)
                }
                return filter.includesPerson(entry)
            }
            alongsideCohorts = Set(anchors.compactMap(Cohort.init))
        }
        func scopedEntries(using filter: StatsSelection.EntryFilter) -> [Ingestion] {
            datedEntries.filter { entry in
                guard matches(entry, filter: filter) else { return false }
                if let alongsideCohorts {
                    return entry.substanceNameUnwrapped != selection.alongside && Cohort(entry).map(alongsideCohorts.contains) == true
                }
                return true
            }
        }
        let entries = scopedEntries(using: filter)
        if let focus = selection.focus, let firstFilter = focus.experienceFilter {
            let eligible = Self(entries: scopedEntries(using: firstFilter), range: range, calendar: calendar)
                .selecting(focus.interval, for: .experiences)
            let experienceIDs = Set(eligible.experiences.map(\.experience.objectID))
            self.init(
                entries: entries.filter { $0.experience.map { experienceIDs.contains($0.objectID) } == true },
                range: eligible.range,
                calendar: calendar
            )
        } else {
            let records = Self(entries: entries, range: range, calendar: calendar)
            self = selection.focus.map { records.selecting($0.interval, for: $0.metric) } ?? records
        }
    }

    private init(entries: [Ingestion], range: DateInterval, calendar: Calendar) {
        self.entries = entries
        self.range = range
        self.calendar = calendar
        var entriesByExperience: [NSManagedObjectID: [Ingestion]] = [:]
        for entry in entries {
            guard let experience = entry.experience else { continue }
            entriesByExperience[experience.objectID, default: []].append(entry)
        }
        experiences = entriesByExperience.values.compactMap { matches in
            guard let experience = matches.first?.experience,
                  let date = matches.compactMap(\.time).min() else { return nil }
            return ExperienceMatch(experience: experience, firstMatchingDate: date, entries: matches)
        }.sorted { $0.firstMatchingDate > $1.firstMatchingDate }
    }

    var daysLogged: Int {
        Set(entries.compactMap(\.time).map { calendar.startOfDay(for: $0) }).count
    }

    var unknownAmountCount: Int { entries.filter { Self.recordedAmount($0) == nil }.count }

    var amounts: [Amount] {
        let groups = Dictionary(grouping: entries) { entry in
            Amount.Key(
                substance: entry.substanceNameUnwrapped,
                unit: entry.unitsUnwrapped,
                customUnitID: entry.customUnit?.objectID
            )
        }
        return groups.compactMap { key, entries in
            let known = entries.compactMap(Self.recordedAmount).sorted()
            guard let minimum = known.first, let maximum = known.last else { return nil }
            let middle = known.count / 2
            let median = known.count.isMultiple(of: 2) ? known[middle - 1] / 2 + known[middle] / 2 : known[middle]
            let total = known.reduce(0, +)
            return Amount(key: key, total: total, count: known.count, average: total / Double(known.count),
                          median: median, minimum: minimum, maximum: maximum,
                          customUnitName: entries.first?.customUnit?.nameUnwrapped)
        }.sorted {
            ($0.key.substance, $0.key.unit, $0.customUnitName ?? "") < ($1.key.substance, $1.key.unit, $1.customUnitName ?? "")
        }
    }

    var gapsBetweenLogs: [Gap] {
        guard Set(entries.map(\.substanceNameUnwrapped)).count == 1,
              Set(entries.map({ Ingestion.storedConsumerName($0.consumerNameUnwrapped) })).count == 1 else { return [] }
        let chronological = entries.sorted { $0.timeUnwrapped < $1.timeUnwrapped }
        return zip(chronological, chronological.dropFirst()).map { older, newer in
            Gap(older: older, newer: newer, duration: newer.timeUnwrapped.timeIntervalSince(older.timeUnwrapped))
        }.reversed()
    }

    var bucketComponent: Calendar.Component {
        if range.duration <= 35 * 86_400 { return .day }
        if range.duration <= 140 * 86_400 { return .weekOfYear }
        if range.duration <= 550 * 86_400 { return .month }
        return .year
    }

    func buckets(for metric: StatsMetric) -> [Bucket] {
        let dates: [Date]
        switch metric {
        case .experiences: dates = experiences.map(\.firstMatchingDate)
        case .ingestions: dates = entries.compactMap(\.time)
        case .gaps: return []
        }

        let byInterval: [DateInterval: Int] = dates.reduce(into: [:]) { counts, date in
            if let interval = calendar.dateInterval(of: bucketComponent, for: date) {
                counts[interval, default: 0] += 1
            }
        }
        return byInterval.map { Bucket(interval: $0.key, count: $0.value) }
            .sorted { $0.interval.start < $1.interval.start }
    }

    func chartDomain(covering buckets: [Bucket]) -> ClosedRange<Date>? {
        guard let first = buckets.first, let last = buckets.last else { return nil }
        let start = range.start == .distantPast ? first.interval.start : min(first.interval.start, range.start)
        let end = range.end == .distantFuture ? last.interval.end : max(last.interval.end, range.end)
        return start...end
    }

    func selecting(_ bucket: Bucket, for metric: StatsMetric) -> Self {
        selecting(bucket.interval, for: metric)
    }

    func selecting(_ selectedInterval: DateInterval, for metric: StatsMetric) -> Self {
        guard let interval = range.intersection(with: selectedInterval) else {
            return Self(entries: [], range: selectedInterval, calendar: calendar)
        }
        if metric == .experiences {
            let matches = experiences.filter { interval.start <= $0.firstMatchingDate && $0.firstMatchingDate < interval.end }
            return Self(entries: matches.flatMap(\.entries), range: interval, calendar: calendar)
        }
        return Self(entries: entries.filter { entry in
            guard let date = entry.time else { return false }
            return interval.start <= date && date < interval.end
        }, range: interval, calendar: calendar)
    }

    private static func recordedAmount(_ ingestion: Ingestion) -> Double? {
        guard let amount = ingestion.doseUnwrapped, amount.isFinite else { return nil }
        return amount
    }
}

struct StatsPeriodControls: View {
    @Binding var period: StatsPeriod
    @Binding var start: Date
    @Binding var end: Date

    var body: some View {
        Picker("Period", selection: $period) {
            ForEach(StatsPeriod.allCases, id: \.self) { period in
                Text(period.title).tag(period)
            }
        }
        if period == .custom {
            let now = Date.now
            DatePicker("From", selection: Binding(
                get: { min(start, now) },
                set: { date in
                    start = date
                    if Calendar.current.compare(date, to: end, toGranularity: .day) == .orderedDescending {
                        end = date
                    }
                }
            ), in: ...now, displayedComponents: .date)
            DatePicker("Through", selection: Binding(
                get: { min(end, now) },
                set: { date in
                    end = date
                    if Calendar.current.compare(date, to: start, toGranularity: .day) == .orderedAscending {
                        start = date
                    }
                }
            ), in: ...now, displayedComponents: .date)
        }
    }
}

struct StatsCoverageRows: View {
    let records: StatsRecords

    var body: some View {
        LabeledContent("Experiences", value: records.experiences.count.formatted())
        LabeledContent("Days Logged", value: records.daysLogged.formatted())
    }
}

struct PinnedStatsView: Codable, Identifiable {
    var id = UUID()
    let name: String
    let metric: StatsMetric
    let selection: StatsSelection
}

struct StatsGoal: Codable, Identifiable {
    enum Metric: String, Codable, CaseIterable {
        case count, amount

        var title: LocalizedStringKey { self == .count ? "Ingestion Count" : "Recorded Amount" }
    }

    var id = UUID()
    var substance: String
    var days = 30
    var metric: Metric = .count
    var target = 0.0
    var unit = ""
    var showsWhenLogging = false

    var isValid: Bool {
        guard !substance.isEmpty, (1...365).contains(days), target.isFinite, target > 0 else { return false }
        switch metric {
        case .count: return target.rounded() == target
        case .amount: return !unit.isEmpty
        }
    }

    func progress(in entries: [Ingestion], endingAt end: Date, calendar: Calendar = .current) -> Progress {
        let start = calendar.date(byAdding: .day, value: 1 - days, to: calendar.startOfDay(for: end)) ?? end
        let entries = entries.filter { entry in
            guard entry.substanceNameUnwrapped == substance, entry.isMine, !entry.isUnconfirmed,
                  let time = entry.time else { return false }
            return start <= time && time <= end
        }
        if metric == .count {
            return Progress(value: Double(entries.count), entries: entries, unknown: [], otherUnits: [])
        }

        let unknown = entries.filter { Self.validAmount($0) == nil }
        let known = entries.filter { Self.validAmount($0) != nil }
        let matching = known.filter { $0.customUnit == nil && $0.unitsUnwrapped == unit }
        let otherUnits = known.filter { $0.customUnit != nil || $0.unitsUnwrapped != unit }
        let value = matching.compactMap(Self.validAmount).reduce(0, +)
        return Progress(value: min(value, Double.greatestFiniteMagnitude), entries: matching, unknown: unknown, otherUnits: otherUnits)
    }

    private static func validAmount(_ entry: Ingestion) -> Double? {
        guard let amount = entry.doseUnwrapped, amount.isFinite, amount > 0 else { return nil }
        return amount
    }

    struct Progress {
        let value: Double
        let entries: [Ingestion]
        let unknown: [Ingestion]
        let otherUnits: [Ingestion]
    }
}
