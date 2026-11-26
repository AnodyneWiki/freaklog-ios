import Charts
import SwiftUI

struct SubstanceOverviewChart: View {
    let substanceData: SubstanceData

    var body: some View {
        Chart(substanceData.last12Months) { element in
            BarMark(
                x: .value("Experiences", element.experienceCount),
                y: .value("Substance", element.displayName)
            )
            .foregroundStyle(by: .value("Substance", element.displayName))
            .opacity(element.substanceName == substanceData.last12Months.first?.substanceName ? 1 : 0.5)
        }
        .chartForegroundStyleScale(mapping: substanceData.color(for:))
        .chartLegend(.hidden)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

struct SubstanceOverview: View {
    let substanceData: SubstanceData

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Substances by Experience", systemImage: "chart.bar.xaxis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            if let mostUsedName = substanceData.last12Months.first?.displayName {
                Text(mostUsedName)
                    .font(.title2.bold())
            } else {
                Text("None")
                    .font(.title2.bold())
            }
            if chartHeight > 0 {
                SubstanceOverviewChart(substanceData: substanceData)
                    .frame(height: chartHeight)
            }
        }
        .padding(.vertical, 6)
    }

    var chartHeight: CGFloat {
        let numberOfRows = substanceData.last12Months.count
        if numberOfRows < 5 {
            return CGFloat(numberOfRows * 20)
        } else {
            return 100
        }
    }
}

#Preview {
    SubstanceOverview(substanceData: .mock1)
        .padding()
}
