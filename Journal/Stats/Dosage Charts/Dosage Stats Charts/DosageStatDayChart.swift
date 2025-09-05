import SwiftUI
import Charts

struct DosageStatDayChart: View {

    let last30Days: [DayDosage]
    let substanceName: String
    let substanceColor: SubstanceColor
    let unit: String
    let isAverageShown: Bool

    var averageDosage: Double {
        let sum = last30Days.map({$0.dosage}).reduce(0, +)
        return sum/30
    }

    var body: some View {
        if !last30Days.isEmpty {
            VStack(alignment: .leading) {
                VStack(alignment: .leading) {
                    Text("Dosage by day")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Last 30 Days")
                        .font(.title2.bold())
                        .foregroundColor(.primary)
                }
                Chart(last30Days, id: \.day) {
                    if isAverageShown {
                        BarMark(
                            x: .value("Day", $0.day, unit: .day),
                            y: .value("Dosage", $0.dosage)
                        )
                        .foregroundStyle(.gray.opacity(0.3))
                        RuleMark(
                            y: .value("Average", averageDosage)
                        )
                        .lineStyle(StrokeStyle(lineWidth: 3))
                        .annotation(position: .top, alignment: .leading) {
                            Text("Average: \(averageDosage.asRoundedReadableString) \(unit) per day")
                                .font(.body.bold())
                                .foregroundStyle(.blue)
                        }
                    } else {
                        BarMark(
                            x: .value("Day", $0.day, unit: .day),
                            y: .value("Dosage", $0.dosage)
                        )
                        .foregroundStyle(substanceColor.swiftUIColor)
                    }
                }.chartYAxisLabel("Dosage in \(unit)")
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 2)) { value in
                            AxisValueLabel(format: .dateTime.day())
                            AxisGridLine()
                            AxisTick()
                        }
                    }
                    .frame(height: 240)
            }
        } else {
            Text("No \(substanceName) ingestions in the last 30 days").foregroundStyle(.secondary)
        }
    }
}

private let oneDay: TimeInterval = 24*60*60

#Preview {
    DosageStatDayChart(
        last30Days: [
            DayDosage(day: .now.addingTimeInterval(-2*oneDay), dosage: 20),
            DayDosage(day: .now.addingTimeInterval(-3*oneDay), dosage: 35),
            DayDosage(day: .now.addingTimeInterval(-6*oneDay), dosage: 70),
            DayDosage(day: .now.addingTimeInterval(-12*oneDay), dosage: 40),
            DayDosage(day: .now.addingTimeInterval(-27*oneDay), dosage: 20),
        ],
        substanceName: "LSD",
        substanceColor: .blue,
        unit: "ug",
        isAverageShown: true
    )
}
