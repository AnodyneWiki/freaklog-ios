import Charts
import SwiftUI

// Bar chart of experiences per day, month or year, with tap/drag selection of one period.
struct ExperienceChart: View {
    let experienceData: ExperienceData
    let timeRange: TimeRange
    var isShowingAverageLine = false
    let colorMapping: (String) -> Color
    var unitLabel: String = "Experiences"
    var chartHeight: CGFloat = 240
    @State private var selectedElement: SubstancePeriodCount?
    @Environment(\.layoutDirection) var layoutDirection

    private var counts: [SubstancePeriodCount] {
        experienceData.counts(in: timeRange)
    }

    func findElement(
        location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) -> SubstancePeriodCount? {
        let relativeXPosition = location.x - geometry[proxy.plotAreaFrame].origin.x
        guard let date = proxy.value(atX: relativeXPosition) as Date? else { return nil }
        return counts.min { abs($0.date.distance(to: date)) < abs($1.date.distance(to: date)) }
    }

    var body: some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                Text("Total \(unitLabel)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("\(experienceData.total(in: timeRange), format: .number) \(unitLabel)")
                    .font(.title2.bold())
                    .foregroundColor(.primary)
            }.opacity(selectedElement == nil ? 1 : 0)
            Chart(counts) {
                let bar = BarMark(
                    x: .value("Date", $0.date, unit: timeRange.period),
                    y: .value("Experiences", $0.experienceCount)
                )
                if isShowingAverageLine {
                    let average = experienceData.average(in: timeRange)
                    bar.foregroundStyle(.gray.opacity(0.3))
                    RuleMark(y: .value("Average", average))
                        .lineStyle(StrokeStyle(lineWidth: 3))
                        .annotation(position: .top, alignment: .leading) {
                            Text("Average: \(average.asRoundedReadableString)")
                                .font(.body.bold())
                                .foregroundStyle(.blue)
                        }
                } else {
                    bar.foregroundStyle(by: .value("Substance", $0.substanceName))
                }
            }
            .chartXAxis {
                if let axisLabelFormat {
                    AxisMarks(values: .stride(by: timeRange.period)) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: axisLabelFormat, centered: true)
                    }
                } else {
                    AxisMarks()
                }
            }
            .chartForegroundStyleScale(mapping: colorMapping)
            .chartLegend(position: .bottom, alignment: .leading)
            .chartOverlay { proxy in
                GeometryReader { nthGeometryItem in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture()
                                .onEnded { value in
                                    let element = findElement(
                                        location: value.location,
                                        proxy: proxy,
                                        geometry: nthGeometryItem
                                    )
                                    if selectedElement?.date == element?.date {
                                        // If tapping the same element, clear the selection.
                                        selectedElement = nil
                                    } else {
                                        selectedElement = element
                                    }
                                }
                                .exclusively(
                                    before: DragGesture(minimumDistance: minimumDistanceForDetectingDragGesture)
                                        .onChanged { value in
                                            selectedElement = findElement(location: value.location, proxy: proxy, geometry: nthGeometryItem)
                                        }
                                )
                        )
                }
            }
            .frame(height: chartHeight)
        }
        .chartBackground { proxy in
            ZStack(alignment: .topLeading) {
                GeometryReader { nthGeoItem in
                    if let selectedElement = selectedElement,
                       let dateInterval = Calendar.current.dateInterval(of: timeRange.period, for: selectedElement.date) {
                        let startPositionX1 = proxy.position(forX: dateInterval.start) ?? 0
                        let startPositionX2 = proxy.position(forX: dateInterval.end) ?? 0
                        let midStartPositionX = (startPositionX1 + startPositionX2) / 2 + nthGeoItem[proxy.plotAreaFrame].origin.x
                        let lineX = layoutDirection == .rightToLeft ? nthGeoItem.size.width - midStartPositionX : midStartPositionX
                        let lineHeight = nthGeoItem[proxy.plotAreaFrame].maxY
                        let boxWidth = selectionBoxWidth
                        let boxOffset = max(0, min(nthGeoItem.size.width - boxWidth, lineX - boxWidth / 2))
                        Rectangle()
                            .fill(.quaternary)
                            .frame(width: 2, height: lineHeight)
                            .position(x: lineX, y: lineHeight / 2)
                        Text(selectedElement.date, format: selectionFormat)
                            .font(.title2.bold())
                            .frame(width: boxWidth, alignment: .center)
                            .foregroundColor(.primary)
                            .background {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(.background)
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(.quaternary.opacity(0.7))
                                }
                                .padding([.leading, .trailing], -8)
                                .padding([.top, .bottom], -4)
                            }
                            .offset(x: boxOffset)
                    }
                }
            }
        }
    }

    // Days use the default axis since a label per day doesn't fit
    private var axisLabelFormat: Date.FormatStyle? {
        switch timeRange {
        case .last30Days: nil
        case .last12Months: .dateTime.month(.narrow)
        case .years: .dateTime.year()
        }
    }

    private var selectionFormat: Date.FormatStyle {
        switch timeRange {
        case .last30Days: .dateTime.year().month().day()
        case .last12Months: .dateTime.year().month()
        case .years: .dateTime.year()
        }
    }

    private var selectionBoxWidth: CGFloat {
        switch timeRange {
        case .last30Days: 150
        case .last12Months: 120
        case .years: 80
        }
    }
}

#Preview {
    List {
        ExperienceChart(
            experienceData: .mock1,
            timeRange: .last12Months,
            colorMapping: ExperienceData.mock1.color(for:)
        )
    }
}
