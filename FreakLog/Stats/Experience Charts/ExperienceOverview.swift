import Charts
import SwiftUI

struct ExperienceOverviewChart: View {
    let experienceData: ExperienceData
    let title: String

    private var timeline: ClosedRange<Date> {
        let calendar = Calendar.current
        let calendarRangeStart = calendar.date(byAdding: .month, value: -12, to: .now) ?? .now
        let dates = experienceData.last12Months.map(\.date)
        let oldest = min(dates.min() ?? calendarRangeStart, calendarRangeStart)
        let newest = max(dates.max() ?? .now, .now)
        let startOfMonth = calendar.dateInterval(of: .month, for: oldest)?.start ?? oldest
        let endOfMonth = calendar.dateInterval(of: .month, for: newest)?.end ?? newest
        return startOfMonth...endOfMonth
    }

    var body: some View {
        Chart(experienceData.last12Months) {
            BarMark(
                x: .value("Month", $0.date, unit: .month),
                y: .value(title, $0.experienceCount)
            )
            .foregroundStyle(by: .value("Substance", $0.substanceName))
        }
        .chartXScale(domain: timeline)
        .chartForegroundStyleScale(mapping: experienceData.color(for:))
        .chartLegend(.hidden)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

struct ExperienceOverview: View {
    let experienceData: ExperienceData
    var showIngestions = false

    private var title: String { showIngestions ? "Ingestions" : "Experiences" }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: showIngestions ? "pills" : "book")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Text(experienceData.total(in: .last12Months), format: .number.precision(.fractionLength(0)))
                .font(.title2.bold().monospacedDigit())
            if !experienceData.last12Months.isEmpty {
                ExperienceOverviewChart(experienceData: experienceData, title: title)
                    .frame(height: 52)
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    ExperienceOverview(experienceData: .mock1)
        .padding()
}
