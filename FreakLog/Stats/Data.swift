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

struct SubstanceData: Hashable, Equatable, Sendable {
    static func == (lhs: SubstanceData, rhs: SubstanceData) -> Bool {
        lhs.years == rhs.years
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(last30Days)
        hasher.combine(last12Months)
        hasher.combine(years)
    }

    let last30Days: [SubstanceCount]
    let last12Months: [SubstanceCount]
    let years: [SubstanceCount]
    let colorMapping: @Sendable (String) -> Color
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
        colorMapping: { substanceName in
            switch substanceName {
            case "MDMA": return Color.pink
            case "Cannabis": return .green
            case "Cocaine": return .blue
            case "Amphetamine": return .cyan
            case "LSD": return .purple
            default: return .red
            }
        }
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
        colorMapping: { substanceName in
            switch substanceName {
            case "MDMA": return Color.pink
            case "Cannabis": return .green
            case "Cocaine": return .blue
            case "Amphetamine": return .cyan
            case "LSD": return .purple
            default: return SubstanceColor.allCases.randomElement()!.swiftUIColor
            }
        }
    )
}

struct SubstanceExperienceCountForDay: Identifiable, Hashable {
    var id: String {
        "\(day.timeIntervalSince1970)\(substanceName)"
    }

    let day: Date
    let substanceName: String
    let experienceCount: Double
}

struct SubstanceExperienceCountForMonth: Hashable {
    let month: Date
    let substanceName: String
    let experienceCount: Double
}

struct SubstanceExperienceCountForYear: Hashable {
    let year: Date
    let substanceName: String
    let experienceCount: Double
}

struct ExperienceData: Hashable, Equatable, Sendable {
    static func == (lhs: ExperienceData, rhs: ExperienceData) -> Bool {
        lhs.years == rhs.years
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(last30Days)
        hasher.combine(last12Months)
        hasher.combine(years)
    }

    let last30Days: [SubstanceExperienceCountForDay]
    let last12Months: [SubstanceExperienceCountForMonth]
    let years: [SubstanceExperienceCountForYear]
    let colorMapping: @Sendable (String) -> Color

    var last30DaysTotal: Double {
        last30Days.map { $0.experienceCount }.reduce(0, +)
    }

    var last12MonthsTotal: Double {
        last12Months.map { $0.experienceCount }.reduce(0, +)
    }

    var yearsTotal: Double {
        years.map { $0.experienceCount }.reduce(0, +)
    }

    var monthlyAverage: Double {
        Self.average(total: last12MonthsTotal, dates: last12Months.map(\.month), per: .month)
    }

    var yearlyAverage: Double {
        Self.average(total: yearsTotal, dates: years.map(\.year), per: .year)
    }

    // Total divided by the number of periods from the first to the last date, empty periods included
    private static func average(total: Double, dates: [Date], per component: Calendar.Component) -> Double {
        guard let minDate = dates.min(), let maxDate = dates.max() else { return 0 }
        let calendar = Calendar.current
        let periodComponents: Set<Calendar.Component> = component == .year ? [.year] : [.year, .month]
        var periods: Set<DateComponents> = [calendar.dateComponents(periodComponents, from: maxDate)]
        var date = minDate
        while date < maxDate {
            periods.insert(calendar.dateComponents(periodComponents, from: date))
            guard let next = calendar.date(byAdding: component, value: 1, to: date) else { break }
            date = next
        }
        return total / Double(periods.count)
    }

    func getSubstanceExperienceCounts(in timeRange: TimeRange) -> [SubstanceExperienceCount] {
        let counts: [(substanceName: String, experienceCount: Double)] = switch timeRange {
        case .last30Days: last30Days.map { ($0.substanceName, $0.experienceCount) }
        case .last12Months: last12Months.map { ($0.substanceName, $0.experienceCount) }
        case .years: years.map { ($0.substanceName, $0.experienceCount) }
        }
        return Dictionary(grouping: counts, by: \.substanceName)
            .map { name, counts in
                SubstanceExperienceCount(
                    substanceName: name,
                    experienceCount: counts.map(\.experienceCount).reduce(0, +),
                    color: colorMapping(name)
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
            .init(day: date(year: 2022, month: 5, day: 8), substanceName: "MDMA", experienceCount: 0.5),
            .init(day: date(year: 2022, month: 5, day: 8), substanceName: "Cannabis", experienceCount: 0.5),
            .init(day: date(year: 2022, month: 5, day: 9), substanceName: "Cannabis", experienceCount: 1),
            .init(day: date(year: 2022, month: 5, day: 10), substanceName: "Cannabis", experienceCount: 1),
            .init(day: date(year: 2022, month: 5, day: 13), substanceName: "Cocaine", experienceCount: 1.0 / 3),
            .init(day: date(year: 2022, month: 5, day: 13), substanceName: "Amphetamine", experienceCount: 1.0 / 3),
            .init(day: date(year: 2022, month: 5, day: 13), substanceName: "LSD", experienceCount: 1.0 / 3),
            .init(day: date(year: 2022, month: 5, day: 14), substanceName: "Cannabis", experienceCount: 1),
            .init(day: date(year: 2022, month: 5, day: 15), substanceName: "MDMA", experienceCount: 1),
            .init(day: date(year: 2022, month: 5, day: 25), substanceName: "Cocaine", experienceCount: 0.5),
            .init(day: date(year: 2022, month: 5, day: 25), substanceName: "MDMA", experienceCount: 0.5),
            .init(day: date(year: 2022, month: 5, day: 27), substanceName: "Cannabis", experienceCount: 0.25),
            .init(day: date(year: 2022, month: 5, day: 27), substanceName: "Amphetamine", experienceCount: 0.25),
            .init(day: date(year: 2022, month: 5, day: 27), substanceName: "MDMA", experienceCount: 0.25),
            .init(day: date(year: 2022, month: 5, day: 27), substanceName: "Cocaine", experienceCount: 0.25),
        ],
        last12Months: [
            .init(month: date(year: 2021, month: 7), substanceName: "MDMA", experienceCount: 1),
            .init(month: date(year: 2021, month: 7), substanceName: "Cocaine", experienceCount: 2),
            .init(month: date(year: 2021, month: 7), substanceName: "Cannabis", experienceCount: 10),
            .init(month: date(year: 2021, month: 8), substanceName: "Cocaine", experienceCount: 1),
            .init(month: date(year: 2021, month: 8), substanceName: "Cannabis", experienceCount: 5),
            .init(month: date(year: 2021, month: 9), substanceName: "Amphetamine", experienceCount: 2),
            .init(month: date(year: 2021, month: 9), substanceName: "Cannabis", experienceCount: 3),
            .init(month: date(year: 2022, month: 1), substanceName: "MDMA", experienceCount: 1),
            .init(month: date(year: 2022, month: 1), substanceName: "Cannabis", experienceCount: 5),
            .init(month: date(year: 2022, month: 3), substanceName: "Amphetamine", experienceCount: 3),
        ],
        years: [
            .init(year: date(year: 2021), substanceName: "MDMA", experienceCount: 3),
            .init(year: date(year: 2021), substanceName: "Cocaine", experienceCount: 4),
            .init(year: date(year: 2021), substanceName: "Cannabis", experienceCount: 20),
            .init(year: date(year: 2021), substanceName: "Amphetamine", experienceCount: 5),
            .init(year: date(year: 2022), substanceName: "MDMA", experienceCount: 5),
            .init(year: date(year: 2022), substanceName: "Cannabis", experienceCount: 15),
            .init(year: date(year: 2022), substanceName: "Amphetamine", experienceCount: 6),
            .init(year: date(year: 2022), substanceName: "Cocaine", experienceCount: 2),
        ],
        colorMapping: { substanceName in
            switch substanceName {
            case "MDMA": return Color.pink
            case "Cannabis": return .green
            case "Cocaine": return .blue
            case "Amphetamine": return .cyan
            case "LSD": return .purple
            default: return .red
            }
        }
    )
}
