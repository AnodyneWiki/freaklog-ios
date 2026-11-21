import SwiftUI
import Charts

struct DosageStatChart: View {
    let data: [DosagePoint]
    let resolution: DosageStatScreen.DosageResolution
    let substanceName: String
    let substanceColor: SubstanceColor
    let unit: String
    let isAverageShown: Bool

    // Yearly averages count every year from the first one up to now, including years without doses
    private var numberOfYears: Int {
        let calendar = Calendar.current
        let firstYear = calendar.component(.year, from: data.map(\.date).min() ?? .now)
        let nowYear = calendar.component(.year, from: .now)
        return max(1, nowYear - firstYear + 1)
    }

    private var averageDosage: Double {
        let sum = data.map(\.dosage).reduce(0, +)
        if resolution == .year {
            return sum / Double(numberOfYears)
        } else {
            return data.isEmpty ? 0 : sum / Double(data.count)
        }
    }

    private var averageLabel: String {
        switch resolution {
        case .day: return "per day"
        case .week: return "per week"
        case .month: return "per month"
        case .year: return "per year in last \(numberOfYears) years"
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
            Text("No \(PersistenceController.shared.displayName(for: substanceName)) ingestions").foregroundStyle(.secondary)
        }
    }

    private var calendarUnit: Calendar.Component {
        resolution.component
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
