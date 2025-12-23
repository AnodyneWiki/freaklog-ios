import SwiftUI
import Charts

struct DosageStatWeekChart: View {

    let weekDosages: [WeekDosage]
    let substanceName: String
    let substanceColor: SubstanceColor
    let unit: String
    let isAverageShown: Bool

    var averageDosage: Double {
        let sum = weekDosages.map({$0.dosage}).reduce(0, +)
        return weekDosages.isEmpty ? 0 : sum/Double(weekDosages.count)
    }

    var body: some View {
        if !weekDosages.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dosage in \(unit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Chart(weekDosages, id: \.week) {
                    if isAverageShown {
                        BarMark(
                            x: .value("Week", $0.week, unit: .weekOfYear),
                            y: .value("Dosage", $0.dosage)
                        )
                        .foregroundStyle(.gray.opacity(0.3))
                        RuleMark(
                            y: .value("Average", averageDosage)
                        )
                        .lineStyle(StrokeStyle(lineWidth: 3))
                        .annotation(position: .top, alignment: .leading) {
                            Text("Average: \(averageDosage.asRoundedReadableString) \(unit) per week")
                                .font(.body.bold())
                                .foregroundStyle(.blue)
                        }
                    } else {
                        BarMark(
                            x: .value("Week", $0.week, unit: .weekOfYear),
                            y: .value("Dosage", $0.dosage)
                        )
                        .foregroundStyle(substanceColor.swiftUIColor)
                    }

                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month, count: 1)) { value in
                        AxisValueLabel(format: .dateTime.month())
                        AxisGridLine()
                        AxisTick()
                    }
                }
                .chartScrollingCompatibility(
                    visibleDomainLength: 26 * 7 * 24 * 60 * 60,
                    initialScrollX: weekDosages.last?.week
                )
                .frame(height: 240)

            }
        } else {
            Text("No \(substanceName) ingestions").foregroundStyle(.secondary)
        }
    }
}

private let oneWeek: TimeInterval = 7*24*60*60

#Preview {
    DosageStatWeekChart(
        weekDosages: [
            WeekDosage(week: .now.addingTimeInterval(-2*oneWeek), dosage: 20),
            WeekDosage(week: .now.addingTimeInterval(-3*oneWeek), dosage: 35),
            WeekDosage(week: .now.addingTimeInterval(-6*oneWeek), dosage: 70),
            WeekDosage(week: .now.addingTimeInterval(-12*oneWeek), dosage: 40),
            WeekDosage(week: .now.addingTimeInterval(-24*oneWeek), dosage: 20),
        ],
        substanceName: "LSD",
        substanceColor: .blue,
        unit: "ug",
        isAverageShown: true
    )
}
