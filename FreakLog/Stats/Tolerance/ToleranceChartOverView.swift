import Charts
import SwiftUI

struct ToleranceChartOverView: View {
    let toleranceWindows: [ToleranceWindow]

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading) {
                Text("Current Tolerance")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                title
                    .font(.title2.bold())
                if !toleranceWindows.isEmpty {
                    Chart {
                        ForEach(toleranceWindows) { window in
                            BarMark(
                                xStart: .value("Start Time", window.start),
                                xEnd: .value("End Time", window.end),
                                y: .value("Substance", window.substanceName)
                            )
                            .foregroundStyle(window.barColor)
                        }
                        RuleMark(x: .value("Current Time", context.date))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                    }
                    .chartLegend(.hidden)
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: chartHeight)
                }
            }
        }
    }

    var title: Text {
        let fullToleranceNames = getSubstanceNamesWithFullTolerance()
        let halfToleranceNames = getSubstanceNamesWithHalfTolerance()
        let allToleranceNames = fullToleranceNames + halfToleranceNames
        if allToleranceNames.isEmpty {
            return Text("Zero tolerance")
        } else {
            return Text(allToleranceNames, format: .list(type: .and))
        }
    }

    var chartHeight: CGFloat {
        let numberOfRows = toleranceWindows.map { $0.substanceName }.uniqued().count
        if numberOfRows < 5 {
            return CGFloat(numberOfRows * 20)
        } else {
            return 100
        }
    }

    private func getSubstanceNamesWithFullTolerance() -> [String] {
        toleranceWindows.filter { window in
            window.toleranceType == .full && window.contains(date: Date.now)
        }.map { window in
            window.substanceName
        }.uniqued()
    }

    private func getSubstanceNamesWithHalfTolerance() -> [String] {
        toleranceWindows.filter { window in
            window.toleranceType == .half && window.contains(date: Date.now)
        }.map { window in
            window.substanceName
        }.uniqued()
    }
}
