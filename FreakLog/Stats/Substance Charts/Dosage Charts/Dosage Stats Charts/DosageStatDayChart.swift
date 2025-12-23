import SwiftUI
import Charts

struct DosageStatDayChart: View {

    let dayDosages: [DayDosage]
    let substanceName: String
    let substanceColor: SubstanceColor
    let unit: String
    let isAverageShown: Bool

    var averageDosage: Double {
        let sum = dayDosages.map({$0.dosage}).reduce(0, +)
        return dayDosages.isEmpty ? 0 : sum/Double(dayDosages.count)
    }

    var body: some View {
        if !dayDosages.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dosage in \(unit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Chart(dayDosages, id: \.day) {
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
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 2)) { value in
                        AxisValueLabel(format: .dateTime.day())
                        AxisGridLine()
                        AxisTick()
                    }
                }
                .chartScrollingCompatibility(
                    visibleDomainLength: 30 * 24 * 60 * 60,
                    initialScrollX: dayDosages.last?.day
                )
                .frame(height: 240)
            }
        } else {
            Text("No \(substanceName) ingestions").foregroundStyle(.secondary)
        }
    }
}

private let oneDay: TimeInterval = 24*60*60

#Preview {
    DosageStatDayChart(
        dayDosages: [
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
