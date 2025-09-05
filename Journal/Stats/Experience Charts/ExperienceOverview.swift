import Charts
import SwiftUI

struct ExperienceOverviewChart: View {
    let experienceData: ExperienceData

    var body: some View {
        Chart(experienceData.last12Months, id: \.month) {
            BarMark(
                x: .value("Month", $0.month, unit: .month),
                y: .value("Experiences", $0.experienceCount)
            )
            .foregroundStyle(by: .value("Substance", $0.substanceName))
        }
        .chartForegroundStyleScale(mapping: experienceData.colorMapping)
        .chartLegend(.hidden)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

struct ExperienceOverview: View {
    let experienceData: ExperienceData

    var body: some View {
        VStack(alignment: .leading) {
            Text("Total Experiences Last 12 Months")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("\(experienceData.last12MonthsTotal, format: .number) Experiences")
                .font(.title2.bold())
            ExperienceOverviewChart(experienceData: experienceData)
                .frame(height: 100)
        }
    }
}

#Preview {
    ExperienceOverview(experienceData: .mock1)
        .padding()
}
