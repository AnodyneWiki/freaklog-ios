import SwiftUI

struct EffectTimeline: View {
    let timelineModel: TimelineModel
    var height: Double = 200
    let timeDisplayStyle: TimeDisplayStyle
    var isShowingCurrentTime = true
    var isShowingTopLabels = true
    var spaceToLabels = 5.0
    private let lineWidth: Double = 5
    private var halfLineWidth: Double {
        lineWidth / 2
    }

    @State private var fingerLocation: CGPoint?

    var body: some View {
        VStack(spacing: 0) {
            if isShowingTopLabels {
                timeLabels
            }
            TimelineView(.everyMinute) { timeline in
                let timelineDate = timeline.date
                Canvas { context, size in
                    let pixelsPerSec = size.width / timelineModel.totalWidth
                    timelineModel.groupDrawables.forEach { groupDrawable in
                        groupDrawable.draw(
                            context: context,
                            height: size.height,
                            pixelsPerSec: pixelsPerSec,
                            lineWidth: lineWidth
                        )
                    }
                    timelineModel.ratingDrawables.forEach { ratingDrawable in
                        ratingDrawable.draw(
                            context: &context,
                            height: size.height,
                            pixelsPerSec: pixelsPerSec,
                            lineWidth: 3
                        )
                    }
                    timelineModel.timedNoteDrawables.forEach { timedNoteDrawable in
                        timedNoteDrawable.draw(
                            context: context,
                            height: size.height,
                            pixelsPerSec: pixelsPerSec,
                            lineWidth: 3
                        )
                    }
                    timelineModel.timeRangeDrawables.forEach { rangeDrawable in
                        rangeDrawable.draw(
                            context: context,
                            height: size.height,
                            pixelsPerSec: pixelsPerSec
                        )
                    }
                    let shouldDrawCurrentTime = timelineDate > timelineModel.startTime.addingTimeInterval(2 * 60) && timelineDate < timelineModel.startTime.addingTimeInterval(timelineModel.totalWidth) && isShowingCurrentTime
                    if shouldDrawCurrentTime {
                        let currentTimeX = (timelineModel.startTime.distance(to: timelineDate) * pixelsPerSec) + halfLineWidth
                        var path = Path()
                        path.move(to: CGPoint(x: currentTimeX, y: 0))
                        path.addLine(to: CGPoint(x: currentTimeX, y: size.height))
                        context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    }
                    if let fingerLocation {
                        // draw vertical line
                        var path = Path()
                        path.move(to: CGPoint(x: fingerLocation.x, y: 0))
                        path.addLine(to: CGPoint(x: fingerLocation.x, y: size.height))
                        let lineWidth: CGFloat = 3
                        context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

                        // draw time text
                        let fingerXInSeconds = fingerLocation.x/size.width * timelineModel.totalWidth
                        let fingerXAsDate = timelineModel.startTime.addingTimeInterval(fingerXInSeconds)
                        let text = getTimeText(time: fingerXAsDate).font(.headline)
                        let resolvedText = context.resolve(text)
                        let textSize = resolvedText.measure(in: size)
                        let verticalDistanceFromFinger: CGFloat = 60
                        let textPaddingLeft: CGFloat = 8
                        let textPaddingTop: CGFloat = 4
                        var topTextY = fingerLocation.y - textSize.height - verticalDistanceFromFinger - 2*textPaddingTop
                        if topTextY < 0 {
                            topTextY = 0
                        }
                        if topTextY > size.height - textSize.height - 2*textPaddingTop {
                            topTextY = size.height - textSize.height - 2*textPaddingTop
                        }
                        var leftTextX = fingerLocation.x - (textSize.width/2) - textPaddingLeft
                        if leftTextX < 0 {
                            leftTextX = 0
                        }
                        if leftTextX + textSize.width + 2*textPaddingLeft > size.width {
                            leftTextX = size.width - textSize.width - 2*textPaddingLeft
                        }
                        let textCenter = CGPoint(x: leftTextX + textSize.width/2 + textPaddingLeft, y: topTextY + (textSize.height/2) + textPaddingTop)
                        let textRect = CGRect(
                            x: leftTextX,
                            y: topTextY,
                            width: textSize.width + 2*textPaddingLeft,
                            height: textSize.height + 2*textPaddingTop
                        )
                        let roundedRectanglePath = RoundedRectangle(cornerRadius: 6, style: .circular).path (in: textRect)
                        context.fill(roundedRectanglePath, with: .color(Color.gray.opacity(0.2)))
                        context.draw(resolvedText, at: textCenter)
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: minimumDistanceForDetectingDragGesture)
                        .onChanged({ drag in
                            fingerLocation = drag.location
                        })
                        .onEnded({ _ in
                            fingerLocation = nil
                        })
                )
            }
            .padding(.vertical, spaceToLabels)
            timeLabels
        }.frame(height: height)
    }

    func getTimeText(time: Date) -> Text {
        if timeDisplayStyle == .relativeToNow {
            if time > .now {
                let durationText = Text(DateDifference.maxTwoUnitsBetween(.now, and: time))
                return Text("in ") + durationText
            } else {
                let durationText = Text(DateDifference.maxTwoUnitsBetween(time, and: .now))
                return durationText + Text(" ago")
            }
        } else if timeDisplayStyle == .relativeToStart {
            return Text(DateDifference.maxTwoUnitsBetween(timelineModel.startTime, and: time)) + Text(" in")
        } else {
            return Text(time, format: Date.FormatStyle().hour().minute())
        }
    }

    private var timeLabels: some View {
        Canvas { context, size in
            let widthInPixels = size.width
            let pixelsPerSec = widthInPixels / timelineModel.totalWidth
            let fullHours = timelineModel.axisDrawable.getFullHours(
                pixelsPerSec: pixelsPerSec,
                widthInPixels: widthInPixels
            )
            fullHours.forEach { fullHour in
                context.draw(
                    Text(fullHour.label).font(.caption),
                    at: CGPoint(x: fullHour.distanceFromStart, y: size.height / 2),
                    anchor: .center
                )
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct EffectTimeline_Previews: PreviewProvider {
    static var previews: some View {
        List {
            Section {
                EffectTimeline(
                    timelineModel: TimelineModel(
                        substanceGroups: substanceGroups,
                        everythingForEachRating: everythingForEachRating,
                        everythingForEachTimedNote: everythingForEachTimedNote,
                        areRedosesDrawnIndividually: false,
                        areSubstanceHeightsIndependent: false
                    ),
                    height: 200,
                    timeDisplayStyle: .regular
                )
            }
        }
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
