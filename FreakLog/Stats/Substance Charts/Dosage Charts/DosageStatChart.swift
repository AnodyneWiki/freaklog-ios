import SwiftUI
import Charts

struct DosageStatChart: View {
    let data: [DosagePoint]
    let resolution: DosageStatScreen.DosageResolution
    let substanceName: String
    let substanceColor: SubstanceColor
    let unit: String
    let isAverageShown: Bool

    private var averageDosage: Double {
        if resolution == .year {
            let calendar = Calendar.current
            let firstYearDate = data.sorted { $0.date < $1.date }.first?.date ?? .now
            let firstYear = calendar.dateComponents([.year], from: firstYearDate).year ?? 0
            let nowYear = calendar.dateComponents([.year], from: .now).year ?? 0
            let numberOfYears = max(1, nowYear - firstYear + 1)
            let sum = data.map(\.dosage).reduce(0, +)
            return sum / Double(numberOfYears)
        } else {
            let sum = data.map(\.dosage).reduce(0, +)
            return data.isEmpty ? 0 : sum / Double(data.count)
        }
    }

    private var averageLabel: String {
        switch resolution {
        case .day: return "per day"
        case .week: return "per week"
        case .month: return "per month"
        case .year: 
            let calendar = Calendar.current
            let firstYearDate = data.sorted { $0.date < $1.date }.first?.date ?? .now
            let firstYear = calendar.dateComponents([.year], from: firstYearDate).year ?? 0
            let nowYear = calendar.dateComponents([.year], from: .now).year ?? 0
            let numberOfYears = max(1, nowYear - firstYear + 1)
            return "per year in last \(numberOfYears) years"
        }
    }

    private var visibleDomainLength: TimeInterval {
        switch resolution {
        case .day: return 30 * 24 * 60 * 60
        case .week: return 26 * 7 * 24 * 60 * 60
        case .month: return 12 * 30.5 * 24 * 60 * 60
        case .year: return 5 * 365 * 24 * 60 * 60
        }
    }

    var body: some View {
        if !data.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dosage in \(unit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Chart(data, id: \.date) { point in
                    if isAverageShown {
                        BarMark(
                            x: .value("Time", point.date, unit: calendarUnit),
                            y: .value("Dosage", point.dosage)
                        )
                        .foregroundStyle(.gray.opacity(0.3))
                        
                        RuleMark(y: .value("Average", averageDosage))
                            .lineStyle(StrokeStyle(lineWidth: 3))
                            .annotation(position: .top, alignment: .leading) {
                                Text("Average: \(averageDosage.asRoundedReadableString) \(unit) \(averageLabel)")
                                    .font(.body.bold())
                                    .foregroundStyle(.blue)
                            }
                    } else {
                        BarMark(
                            x: .value("Time", point.date, unit: calendarUnit),
                            y: .value("Dosage", point.dosage)
                        )
                        .foregroundStyle(substanceColor.swiftUIColor)
                    }
                }
                .chartXAxis {
                    axisMarks
                }
                .chartScrollingCompatibility(
                    visibleDomainLength: visibleDomainLength,
                    initialScrollX: data.last?.date
                )
                .frame(height: 240)
            }
        } else {
            Text("No \(substanceName) ingestions").foregroundStyle(.secondary)
        }
    }

    private var calendarUnit: Calendar.Component {
        switch resolution {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }

    @AxisContentBuilder
    private var axisMarks: some AxisContent {
        switch resolution {
        case .day:
            AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                AxisValueLabel(format: .dateTime.day())
                AxisGridLine()
                AxisTick()
            }
        case .week:
            AxisMarks(values: .stride(by: .month, count: 1)) { _ in
                AxisValueLabel(format: .dateTime.month())
                AxisGridLine()
                AxisTick()
            }
        case .month:
            AxisMarks(values: .stride(by: .month, count: 1)) { _ in
                AxisValueLabel(format: .dateTime.month())
            }
        case .year:
            AxisMarks(values: .stride(by: .year, count: 1)) { _ in
                AxisValueLabel(format: .dateTime.year())
            }
        }
    }
}
