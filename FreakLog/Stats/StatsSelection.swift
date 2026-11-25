import CoreData
import SwiftUI

enum StatsPeriod: String, CaseIterable, Codable {
    case last7Days
    case last30Days
    case last12Months
    case allTime
    case custom

    var title: LocalizedStringKey {
        switch self {
        case .last7Days: "Last 7 Days"
        case .last30Days: "Last 30 Days"
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
    var substance: String?
    var route: AdministrationRoute?
    var person: Person = .me
    var tag: String?
    var matchesPrimaryTagOnly = false

    func forSubstance(_ name: String) -> Self {
        var copy = self
        copy.substance = name
        return copy
    }

    var hasFilters: Bool { substance != nil || route != nil || tag != nil || person != .me }

    func dateRange(now: Date, calendar: Calendar = .current) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let until = now.addingTimeInterval(0.001)
        switch period {
        case .last7Days:
            return DateInterval(start: calendar.date(byAdding: .day, value: -6, to: today) ?? today, end: until)
        case .last30Days:
            return DateInterval(start: calendar.date(byAdding: .day, value: -29, to: today) ?? today, end: until)
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
        if let substance, substance != ingestion.substanceNameUnwrapped { return false }
        if let route, route != ingestion.administrationRouteUnwrapped { return false }
        if let tag {
            if matchesPrimaryTagOnly {
                guard tags.primary.map(PersonalSubstanceTags.key) == PersonalSubstanceTags.key(tag) else {
                    return false
                }
            } else if !tags.contains(tag) {
                return false
            }
        }

        switch person {
        case .me: return ingestion.isMine
        case .everyone: return true
        case .named(let name): return ingestion.consumerNameUnwrapped == name
        }
    }
}

struct StatsRecords {
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
        let range = selection.dateRange(now: now, calendar: calendar)
        let matches = entries.filter { ingestion in
            guard let time = ingestion.time, range.start <= time, time < range.end else { return false }
            return selection.includes(ingestion, tags: tags[ingestion.substanceNameUnwrapped, default: PersonalSubstanceTags()])
        }
        self.init(entries: matches, range: range, calendar: calendar)
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
        guard let interval = range.intersection(with: bucket.interval) else { return self }
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
