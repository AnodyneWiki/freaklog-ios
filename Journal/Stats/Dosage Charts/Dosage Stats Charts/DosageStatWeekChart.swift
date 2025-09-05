import SwiftUI
import Charts

struct DosageStatWeekChart: View {

    let last26Weeks: [WeekDosage]
    let substanceName: String
    let substanceColor: SubstanceColor
    let unit: String
    let isAverageShown: Bool

    var averageDosage: Double {
        let sum = last26Weeks.map({$0.dosage}).reduce(0, +)
        return sum/26
    }

    var body: some View {
        if !last26Weeks.isEmpty {
            VStack(alignment: .leading) {
                VStack(alignment: .leading) {
                    Text("Dosage by week")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Last 26 Weeks")
                        .font(.title2.bold())
                        .foregroundColor(.primary)
                }
                Chart(last26Weeks, id: \.week) {
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

                }.chartYAxisLabel("Dosage in \(unit)")
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .month, count: 1)) { value in
                            AxisValueLabel(format: .dateTime.month())
                            AxisGridLine()
                            AxisTick()
                        }
                    }
                    .frame(height: 240)

            }
        } else {
            Text("No \(substanceName) ingestions in the last 26 weeks").foregroundStyle(.secondary)
        }
    }
}

private let oneWeek: TimeInterval = 7*24*60*60

#Preview {
    DosageStatWeekChart(
        last26Weeks: [
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
