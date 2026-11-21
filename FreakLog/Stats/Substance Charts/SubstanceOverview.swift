import Charts
import SwiftUI

struct SubstanceOverviewChart: View {
    let substanceData: SubstanceData

    var body: some View {
        Chart(substanceData.last12Months) { element in
            BarMark(
                x: .value("Experiences", element.experienceCount),
                y: .value("Substance", element.substanceName)
            )
            .foregroundStyle(by: .value("Substance", element.substanceName))
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
        VStack(alignment: .leading) {
            Text("Most Experiences Last 12 Months")
                .foregroundStyle(.secondary)
            if let mostUsedName = substanceData.last12Months.first?.substanceName {
                Text(mostUsedName)
                    .font(.title2.bold())
            } else {
                Text("None")
                    .font(.title2.bold())
            }
            SubstanceOverviewChart(substanceData: substanceData)
                .frame(height: chartHeight)
        }
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
