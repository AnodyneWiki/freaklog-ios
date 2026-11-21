import SwiftUI

func date(year: Int, month: Int = 1, day: Int = 1) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
}

struct SubstanceCount: Identifiable, Hashable {
    var id: String {
        substanceName
    }

    let substanceName: String
    let experienceCount: Int
}

struct SubstanceData: Hashable, Sendable {
    let last30Days: [SubstanceCount]
    let last12Months: [SubstanceCount]
    let years: [SubstanceCount]
    let colors: [String: Color]

    func counts(in timeRange: TimeRange) -> [SubstanceCount] {
        switch timeRange {
        case .last30Days: last30Days
        case .last12Months: last12Months
        case .years: years
        }
    }

    func color(for substanceName: String) -> Color {
        colors[substanceName] ?? SubstanceColor.fallback.swiftUIColor
    }
}

extension SubstanceData {
    static let mock1 = SubstanceData(
        last30Days: [
            .init(substanceName: "Cannabis", experienceCount: 15),
            .init(substanceName: "Cocaine", experienceCount: 8),
            .init(substanceName: "Amphetamine", experienceCount: 3),
            .init(substanceName: "MDMA", experienceCount: 1),
        ],
        last12Months: [
            .init(substanceName: "Cannabis", experienceCount: 55),
            .init(substanceName: "Cocaine", experienceCount: 10),
            .init(substanceName: "MDMA", experienceCount: 4),
            .init(substanceName: "Amphetamine", experienceCount: 3),
        ],
        years: [
            .init(substanceName: "Cannabis", experienceCount: 60),
            .init(substanceName: "Cocaine", experienceCount: 15),
            .init(substanceName: "MDMA", experienceCount: 8),
            .init(substanceName: "Amphetamine", experienceCount: 8),
        ],
        colors: [
            "MDMA": .pink,
            "Cannabis": .green,
            "Cocaine": .blue,
            "Amphetamine": .cyan,
            "LSD": .purple,
        ]
    )
    static let mock2 = SubstanceData(
        last30Days: [
            .init(substanceName: "Cannabis", experienceCount: 15),
            .init(substanceName: "Cocaine", experienceCount: 8),
            .init(substanceName: "Amphetamine", experienceCount: 3),
            .init(substanceName: "MDMA", experienceCount: 1),
        ],
        last12Months: [
            .init(substanceName: "Cannabis", experienceCount: 55),
            .init(substanceName: "Cocaine", experienceCount: 10),
            .init(substanceName: "MDMA", experienceCount: 4),
            .init(substanceName: "Substance 1", experienceCount: 4),
            .init(substanceName: "Substance 2", experienceCount: 4),
            .init(substanceName: "Substance 3", experienceCount: 4),
            .init(substanceName: "Substance 4", experienceCount: 4),
            .init(substanceName: "Substance 5", experienceCount: 4),
            .init(substanceName: "Substance 6", experienceCount: 4),
            .init(substanceName: "Substance 7", experienceCount: 4),
            .init(substanceName: "Substance 8", experienceCount: 4),
            .init(substanceName: "Substance 9", experienceCount: 4),
            .init(substanceName: "Substance 10", experienceCount: 4),
            .init(substanceName: "Substance 11", experienceCount: 4),
            .init(substanceName: "Substance 12", experienceCount: 4),
            .init(substanceName: "Substance 13", experienceCount: 4),
            .init(substanceName: "Substance 14", experienceCount: 4),
            .init(substanceName: "Substance 15", experienceCount: 4),
            .init(substanceName: "Substance 16", experienceCount: 4),
            .init(substanceName: "Substance 17", experienceCount: 4),
            .init(substanceName: "Substance 18", experienceCount: 4),
            .init(substanceName: "Substance 19", experienceCount: 4),
            .init(substanceName: "Substance 20", experienceCount: 4),
            .init(substanceName: "Substance 21", experienceCount: 4),
            .init(substanceName: "Substance 22", experienceCount: 4),
            .init(substanceName: "Substance 23", experienceCount: 4),
            .init(substanceName: "Substance 24", experienceCount: 4),
            .init(substanceName: "Substance 25", experienceCount: 4),
            .init(substanceName: "Substance 26", experienceCount: 4),
            .init(substanceName: "Substance 27", experienceCount: 4),
            .init(substanceName: "Substance 28", experienceCount: 4),
            .init(substanceName: "Substance 29", experienceCount: 4),
            .init(substanceName: "Substance 30", experienceCount: 4),
            .init(substanceName: "Substance 31", experienceCount: 4),
            .init(substanceName: "Amphetamine", experienceCount: 3),
        ],
        years: [
            .init(substanceName: "Cannabis", experienceCount: 60),
            .init(substanceName: "Cocaine", experienceCount: 15),
            .init(substanceName: "MDMA", experienceCount: 8),
            .init(substanceName: "Amphetamine", experienceCount: 8),
        ],
        colors: [
            "MDMA": .pink,
            "Cannabis": .green,
            "Cocaine": .blue,
            "Amphetamine": .cyan,
            "LSD": .purple,
        ]
    )
}

// Experiences (or ingestions) of one substance within one day, month or year
struct SubstancePeriodCount: Identifiable, Hashable {
    var id: String {
        "\(date.timeIntervalSince1970)\(substanceName)"
    }

    let date: Date
    let substanceName: String
    let experienceCount: Double
}

struct ExperienceData: Hashable, Sendable {
    let last30Days: [SubstancePeriodCount]
    let last12Months: [SubstancePeriodCount]
    let years: [SubstancePeriodCount]
    let colors: [String: Color]

    func color(for substanceName: String) -> Color {
        colors[substanceName] ?? SubstanceColor.fallback.swiftUIColor
    }

    func counts(in timeRange: TimeRange) -> [SubstancePeriodCount] {
        switch timeRange {
        case .last30Days: last30Days
        case .last12Months: last12Months
        case .years: years
        }
    }

    func total(in timeRange: TimeRange) -> Double {
        counts(in: timeRange).map(\.experienceCount).reduce(0, +)
    }

    // Total divided by the number of periods from the first to the last date, empty periods included
    func average(in timeRange: TimeRange) -> Double {
        let dates = counts(in: timeRange).map(\.date)
        guard let minDate = dates.min(), let maxDate = dates.max() else { return 0 }
        let calendar = Calendar.current
        var periods: Set<DateComponents> = [calendar.dateComponents(timeRange.periodComponents, from: maxDate)]
        var date = minDate
        while date < maxDate {
            periods.insert(calendar.dateComponents(timeRange.periodComponents, from: date))
            guard let next = calendar.date(byAdding: timeRange.period, value: 1, to: date) else { break }
            date = next
        }
        return total(in: timeRange) / Double(periods.count)
    }

    func getSubstanceExperienceCounts(in timeRange: TimeRange) -> [SubstanceExperienceCount] {
        Dictionary(grouping: counts(in: timeRange), by: \.substanceName)
            .map { name, counts in
                SubstanceExperienceCount(
                    substanceName: name,
                    experienceCount: counts.map(\.experienceCount).reduce(0, +),
                    color: color(for: name)
                )
            }
            .filter { $0.experienceCount > 0 }
            .sorted()
    }
}

struct SubstanceExperienceCount: Identifiable, Comparable {
    static func < (lhs: SubstanceExperienceCount, rhs: SubstanceExperienceCount) -> Bool {
        lhs.experienceCount > rhs.experienceCount
    }

    var id: String {
        substanceName
    }

    let substanceName: String
    let experienceCount: Double
    let color: Color
}

extension ExperienceData {
    static let mock1 = ExperienceData(
        last30Days: [
            .init(date: date(year: 2022, month: 5, day: 8), substanceName: "MDMA", experienceCount: 0.5),
            .init(date: date(year: 2022, month: 5, day: 8), substanceName: "Cannabis", experienceCount: 0.5),
            .init(date: date(year: 2022, month: 5, day: 9), substanceName: "Cannabis", experienceCount: 1),
            .init(date: date(year: 2022, month: 5, day: 10), substanceName: "Cannabis", experienceCount: 1),
            .init(date: date(year: 2022, month: 5, day: 13), substanceName: "Cocaine", experienceCount: 1.0 / 3),
            .init(date: date(year: 2022, month: 5, day: 13), substanceName: "Amphetamine", experienceCount: 1.0 / 3),
            .init(date: date(year: 2022, month: 5, day: 13), substanceName: "LSD", experienceCount: 1.0 / 3),
            .init(date: date(year: 2022, month: 5, day: 14), substanceName: "Cannabis", experienceCount: 1),
            .init(date: date(year: 2022, month: 5, day: 15), substanceName: "MDMA", experienceCount: 1),
            .init(date: date(year: 2022, month: 5, day: 25), substanceName: "Cocaine", experienceCount: 0.5),
            .init(date: date(year: 2022, month: 5, day: 25), substanceName: "MDMA", experienceCount: 0.5),
            .init(date: date(year: 2022, month: 5, day: 27), substanceName: "Cannabis", experienceCount: 0.25),
            .init(date: date(year: 2022, month: 5, day: 27), substanceName: "Amphetamine", experienceCount: 0.25),
            .init(date: date(year: 2022, month: 5, day: 27), substanceName: "MDMA", experienceCount: 0.25),
            .init(date: date(year: 2022, month: 5, day: 27), substanceName: "Cocaine", experienceCount: 0.25),
        ],
        last12Months: [
            .init(date: date(year: 2021, month: 7), substanceName: "MDMA", experienceCount: 1),
            .init(date: date(year: 2021, month: 7), substanceName: "Cocaine", experienceCount: 2),
            .init(date: date(year: 2021, month: 7), substanceName: "Cannabis", experienceCount: 10),
            .init(date: date(year: 2021, month: 8), substanceName: "Cocaine", experienceCount: 1),
            .init(date: date(year: 2021, month: 8), substanceName: "Cannabis", experienceCount: 5),
            .init(date: date(year: 2021, month: 9), substanceName: "Amphetamine", experienceCount: 2),
            .init(date: date(year: 2021, month: 9), substanceName: "Cannabis", experienceCount: 3),
            .init(date: date(year: 2022, month: 1), substanceName: "MDMA", experienceCount: 1),
            .init(date: date(year: 2022, month: 1), substanceName: "Cannabis", experienceCount: 5),
            .init(date: date(year: 2022, month: 3), substanceName: "Amphetamine", experienceCount: 3),
        ],
        years: [
            .init(date: date(year: 2021), substanceName: "MDMA", experienceCount: 3),
            .init(date: date(year: 2021), substanceName: "Cocaine", experienceCount: 4),
            .init(date: date(year: 2021), substanceName: "Cannabis", experienceCount: 20),
            .init(date: date(year: 2021), substanceName: "Amphetamine", experienceCount: 5),
            .init(date: date(year: 2022), substanceName: "MDMA", experienceCount: 5),
            .init(date: date(year: 2022), substanceName: "Cannabis", experienceCount: 15),
            .init(date: date(year: 2022), substanceName: "Amphetamine", experienceCount: 6),
            .init(date: date(year: 2022), substanceName: "Cocaine", experienceCount: 2),
        ],
        colors: [
            "MDMA": .pink,
            "Cannabis": .green,
            "Cocaine": .blue,
            "Amphetamine": .cyan,
            "LSD": .purple,
        ]
    )
}
