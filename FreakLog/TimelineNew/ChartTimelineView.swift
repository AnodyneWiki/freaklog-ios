import SwiftUI
import Charts

struct ChartTimelineView: View {
    let timelineModel: ChartTimelineModel
    var height: Double = 200
    // var timeDisplayStyle: TimeDisplayStyle // TODO
    var isShowingCurrentTime = true
    
    @State private var selectedTime: Date?
    
    var body: some View {
        Chart {
            // Areas and Lines
            ForEach(timelineModel.series) { series in
                chartSeries(series)
            }
            
            // Ratings
            ForEach(timelineModel.ratingEvents) { rating in
                ratingMark(rating)
            }
            
            // Note Events
            ForEach(timelineModel.noteEvents) { note in
                noteMark(note)
            }
            
            // Current Time Line
            if isShowingCurrentTime {
                currentRuleMark
            }
            
            // Interaction Selection Rule
            if let selectedTime {
                selectionRuleMark(selectedTime)
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic) { value in
                AxisValueLabel(format: .dateTime.hour())
                AxisTick()
                AxisGridLine()
            }
        }
        .chartXScale(domain: timelineModel.startTime ... timelineModel.startTime.addingTimeInterval(timelineModel.totalWidth))
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let x = value.location.x - geometry[proxy.plotAreaFrame].origin.x
                                if let date: Date = proxy.value(atX: x) {
                                    // Snap to nearest minute? Or just raw
                                    selectedTime = date
                                }
                            }
                            .onEnded { _ in
                                selectedTime = nil
                            }
                    )
            }
        }
        .chartYScale(domain: -0.01...1.01) // Fixed scale (Normalized) with padding for thick stroke fill
        .frame(height: height)
        .background(Color.black) // Dark background
        .transaction { transaction in
            transaction.animation = nil // Disable all animations to prevent blinking
        }
    }
    
    // MARK: - Subviews
    
    @ChartContentBuilder
    func chartSeries(_ series: ChartTimelineModel.TimelineSeries) -> some ChartContent {
        ForEach(series.events) { event in
            if event.style == .solid {
                solidEventMarks(series: series, event: event)
            } else { // Dashed
                dashedEventMarks(series: series, event: event)
            }
        }
        
        // Ingestion Points (Dots)
        ForEach(series.ingestionPoints) { point in
            PointMark(
                x: .value("Time", point.time),
                y: .value("Value", point.value)
            )
            .foregroundStyle(series.color)
            .symbolSize(100)
        }
    }
    
    @ChartContentBuilder
    func solidEventMarks(series: ChartTimelineModel.TimelineSeries, event: ChartTimelineModel.TimelineEvent) -> some ChartContent {
        // Area
        ForEach(event.points) { point in
            AreaMark(
                x: .value("Time", point.time),
                yStart: .value("Base", -0.01),
                yEnd: .value("Value", point.value),
                series: .value("Substance", "\(series.id)-solid-\(event.id)")
            )
            .foregroundStyle(series.color.opacity(0.2)) // Match shapeOpacity
            .interpolationMethod(.linear)
        }
        
        // Line Border
        ForEach(event.points) { point in
            LineMark(
                x: .value("Time", point.time),
                y: .value("Value", point.value),
                series: .value("Substance", "\(series.id)-solid-\(event.id)")
            )
            .foregroundStyle(series.color) // Solid line
            .lineStyle(StrokeStyle(lineWidth: 5)) // Thicker solid line
            .interpolationMethod(.linear)
        }
    }
    
    @ChartContentBuilder
    func dashedEventMarks(series: ChartTimelineModel.TimelineSeries, event: ChartTimelineModel.TimelineEvent) -> some ChartContent {
        // Line Only (Dashed)
        ForEach(event.points) { point in
            LineMark(
                x: .value("Time", point.time),
                y: .value("Value", point.value),
                series: .value("Substance", "\(series.id)-dashed-\(event.id)")
            )
            .foregroundStyle(series.color)
            .lineStyle(StrokeStyle(
                lineWidth: 5,
                lineCap: .round,
                lineJoin: .round,
                dash: [10, 10],
                dashPhase: 0
            )) // Thicker Dashed
            .interpolationMethod(.linear) // Already sampled
        }
        
        // Area (filled)
        ForEach(event.points) { point in
            AreaMark(
                x: .value("Time", point.time),
                yStart: .value("Base", -0.01),
                yEnd: .value("Value", point.value),
                series: .value("Substance", "\(series.id)-dashed-\(event.id)")
            )
            .foregroundStyle(series.color.opacity(0.2))
            .interpolationMethod(.linear)
        }
    }
    
    @ChartContentBuilder
    func ratingMark(_ rating: ChartTimelineModel.RatingEvent) -> some ChartContent {
        PointMark(
            x: .value("Time", rating.time),
            y: .value("Value", 0)
        )
        .symbol {
           // Draw rating UI
           Circle().fill(Color.yellow).frame(width: 10, height: 10) // Placeholder
        }
    }
    
    @ChartContentBuilder
    func noteMark(_ note: ChartTimelineModel.NoteEvent) -> some ChartContent {
        PointMark(
            x: .value("Time", note.time),
            y: .value("Value", 0)
        )
        .foregroundStyle(note.color)
    }
    
    @ChartContentBuilder
    var currentRuleMark: some ChartContent {
        RuleMark(x: .value("Now", Date.now))
            .foregroundStyle(Color.white) // Bright color
            .lineStyle(StrokeStyle(lineWidth: 2))
            .annotation(position: .top) {
                // Current time label if needed
            }
    }
    
    @ChartContentBuilder
    func selectionRuleMark(_ selectedTime: Date) -> some ChartContent {
        RuleMark(x: .value("Selected", selectedTime))
            .foregroundStyle(Color.gray.opacity(0.5))
            .annotation(position: .top) {
                Text(selectedTime.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .padding(4)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
            }
    }
}

// Previews
struct ChartTimelineView_Previews: PreviewProvider {
    static var previews: some View {
        ChartTimelineView(
            timelineModel: ChartTimelineModel(
                substanceGroups: substanceGroups,
                everythingForEachRating: everythingForEachRating,
                everythingForEachTimedNote: everythingForEachTimedNote,
                areRedosesDrawnIndividually: false,
                areSubstanceHeightsIndependent: false
            ),
            height: 200
        )
        .previewLayout(.sizeThatFits)
    }

    static let everythingForEachRating: [EverythingForOneRating] = [
        EverythingForOneRating(
            time: Date().addingTimeInterval(-2 * 60 * 60),
            option: .fourPlus
        ),
        EverythingForOneRating(
            time: Date().addingTimeInterval(-1 * 60 * 60),
            option: .plus
        ),
    ]

    static let everythingForEachTimedNote: [EverythingForOneTimedNote] = [
        EverythingForOneTimedNote(
            time: Date().addingTimeInterval(-2 * 60 * 60),
            color: .blue
        ),
        EverythingForOneTimedNote(
            time: Date().addingTimeInterval(-1 * 60 * 60),
            color: .green
        ),
    ]

    static let substanceGroups: [SubstanceIngestionGroup] = [
        SubstanceIngestionGroup(
            substanceName: "MDMA",
            color: .blue,
            routeMinInfos: [
                RouteMinInfo(
                    route: .oral,
                    ingestions: [
                        IngestionMinInfo(
                            dose: 100,
                            time: .now.addingTimeInterval(-2 * 60 * 60),
                            endTime: nil,
                            onsetDelayInHours: 0
                        ),
                        IngestionMinInfo(
                            dose: 50,
                            time: .now,
                            endTime: nil,
                            onsetDelayInHours: 0
                        ),
                    ]
                ),
            ]
        ),
        SubstanceIngestionGroup(
            substanceName: "Cannabis",
            color: .green,
            routeMinInfos: [
                RouteMinInfo(
                    route: .oral,
                    ingestions: [
                        IngestionMinInfo(
                            dose: 40,
                            time: .now.addingTimeInterval(-3 * 60 * 60),
                            endTime: .now.addingTimeInterval(-0.5 * 60 * 60),
                            onsetDelayInHours: 0
                        ),
                    ]
                ),
            ]
        ),
        SubstanceIngestionGroup(
            substanceName: "Tramadol",
            color: .yellow,
            routeMinInfos: [
                RouteMinInfo(
                    route: .oral,
                    ingestions: [
                        IngestionMinInfo(
                            dose: 40,
                            time: .now.addingTimeInterval(-5 * 60 * 60),
                            endTime: .now.addingTimeInterval(-2 * 60 * 60),
                            onsetDelayInHours: 0
                        ),
                    ]
                ),
            ]
        ),
        SubstanceIngestionGroup(
            substanceName: "Tramadol",
            color: .yellow,
            routeMinInfos: [
                RouteMinInfo(
                    route: .oral,
                    ingestions: [
                        IngestionMinInfo(
                            dose: 40,
                            time: .now.addingTimeInterval(-0.2 * 60 * 60),
                            endTime: .now.addingTimeInterval(2 * 60 * 60),
                            onsetDelayInHours: 0
                        ),
                    ]
                ),
            ]
        ),
        SubstanceIngestionGroup(
            substanceName: "LSD",
            color: .pink,
            routeMinInfos: [
                RouteMinInfo(route: .sublingual, ingestions: [
                    IngestionMinInfo(
                        dose: 100,
                        time: .now.addingTimeInterval(-4 * 60 * 60),
                        endTime: nil,
                        onsetDelayInHours: 0
                    ),
                ]),
            ]
        ),
    ]
}

