import SwiftUI
import Charts

struct DosageStatMonthChart: View {

    let monthDosages: [MonthDosage]
    let substanceName: String
    let substanceColor: SubstanceColor
    let unit: String
    let isAverageShown: Bool

    var averageDosage: Double {
        let sum = monthDosages.map({$0.dosage}).reduce(0, +)
        return monthDosages.isEmpty ? 0 : sum/Double(monthDosages.count)
    }


    var body: some View {
        if !monthDosages.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dosage in \(unit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Chart(monthDosages, id: \.month) {
                    if isAverageShown {
                        BarMark(
                            x: .value("Month", $0.month, unit: .month),
                            y: .value("Dosage", $0.dosage)
                        )
                        .foregroundStyle(.gray.opacity(0.3))
                        RuleMark(
                            y: .value("Average", averageDosage)
                        )
                        .lineStyle(StrokeStyle(lineWidth: 3))
                        .annotation(position: .top, alignment: .leading) {
                            Text("Average: \(averageDosage.asRoundedReadableString) \(unit) per month")
                                .font(.body.bold())
                                .foregroundStyle(.blue)
                        }
                    } else {
                        BarMark(
                            x: .value("Month", $0.month, unit: .month),
                            y: .value("Dosage", $0.dosage)
                        )
                        .foregroundStyle(substanceColor.swiftUIColor)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month, count: 1)) { value in
                        AxisValueLabel(format: .dateTime.month())
                    }
                }
                .chartScrollingCompatibility(
                    visibleDomainLength: 12 * 30.5 * 24 * 60 * 60,
                    initialScrollX: monthDosages.last?.month
                )
                .frame(height: 240)
            }
        } else {
            Text("No \(substanceName) ingestions").foregroundStyle(.secondary)
        }
    }
}

private let oneMonth: TimeInterval = 30*24*60*60

#Preview {
    DosageStatMonthChart(
        monthDosages: [
            MonthDosage(month: .now.addingTimeInterval(-2*oneMonth), dosage: 20),
            MonthDosage(month: .now.addingTimeInterval(-3*oneMonth), dosage: 35),
            MonthDosage(month: .now.addingTimeInterval(-6*oneMonth), dosage: 70),
            MonthDosage(month: .now.addingTimeInterval(-7*oneMonth), dosage: 40),
            MonthDosage(month: .now.addingTimeInterval(-11*oneMonth), dosage: 20),
        ],
        substanceName: "LSD",
        substanceColor: .blue,
        unit: "ug",
        isAverageShown: true
    )
}
