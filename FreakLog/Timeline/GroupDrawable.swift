import SwiftUI

struct GroupDrawable {
    private let color: SubstanceColor

    private var timelineDrawables: [TimelineDrawable]

    var endRelativeToStartInSeconds: TimeInterval {
        timelineDrawables.map { $0.endOfLineRelativeToStartInSeconds }.max() ?? 0
    }

    let startInSeconds: TimeInterval

    var nonNormalizedHeight: Double {
        timelineDrawables.map { drawable in
            drawable.nonNormalizedHeight
        }.max() ?? 1
    }

    mutating func normalize(maxHeight: Double) {
        for (index, _) in timelineDrawables.enumerated() {
            timelineDrawables[index].nonNormalizedOverallMax = maxHeight
        }
    }

    let hasDurationInfo: Bool

    // swiftlint:disable function_body_length
    init(
        startGraph: Date,
        color: SubstanceColor,
        roaDuration: RoaDuration?,
        weightedLines: [WeightedLine],
        areRedosesDrawnIndividually: Bool,
        areSubstanceHeightsIndependent: Bool
    ) {
        self.color = color
        let startDate = weightedLines.map({ line in
            line.startTime
        }).min() ?? .now
        self.startInSeconds = startGraph.distance(to: startDate)
        self.hasDurationInfo = roaDuration != nil
        let nonNormalizedMaxOfRoute = weightedLines.map({$0.strengthRelativeToCommonDose}).max() ?? 1
        
        let weightedLinesForPointIngestions = weightedLines.filter { $0.endTime == nil}
        let weightedLinesForRangeIngestions = weightedLines.filter { $0.endTime != nil}

        guard let roaDuration else {
            timelineDrawables = weightedLinesForPointIngestions.map { weightedLine in
                NoTimeline(
                    onsetDelayInHours: weightedLine.onsetDelayInHours,
                    ingestionTimeRelativeToStartInSeconds: GroupDrawable.getDistanceFromStartGraphInSeconds(graphStartTime: startGraph, time: weightedLine.startTime)
                )
            }
            return
        }

        let makeTimeline = { (weightedLine: WeightedLine) -> TimelineDrawable in
            UnifiedTimelineDrawable(
                onset: roaDuration.onset?.maybeFullDurationRange,
                comeup: roaDuration.comeup?.maybeFullDurationRange,
                peak: roaDuration.peak?.maybeFullDurationRange,
                offset: roaDuration.offset?.maybeFullDurationRange,
                total: roaDuration.total?.maybeFullDurationRange,
                onsetDelayInHours: weightedLine.onsetDelayInHours,
                ingestionTimeRelativeToStartInSeconds: GroupDrawable.getDistanceFromStartGraphInSeconds(
                    graphStartTime: startGraph,
                    time: weightedLine.startTime
                ),
                nonNormalizedHeight: weightedLine.strengthRelativeToCommonDose,
                nonNormalizedMaxOfRoute: nonNormalizedMaxOfRoute,
                areSubstanceHeightsIndependent: areSubstanceHeightsIndependent,
                peakWeight: weightedLine.horizontalWeight,
                offsetWeight: weightedLine.horizontalWeight,
                totalWeight: weightedLine.horizontalWeight
            )
        }

        // Redoses add up into one curve unless drawn individually, which needs all four phases
        var results: [TimelineDrawable] = []
        if !weightedLinesForPointIngestions.isEmpty {
            let cumulative = areRedosesDrawnIndividually ? nil : roaDuration.toFullCumulativeTimeline(
                weightedLines: weightedLines,
                graphStartTime: startGraph,
                areSubstanceHeightsIndependent: areSubstanceHeightsIndependent
            )
            results = cumulative.map { [$0] } ?? weightedLinesForPointIngestions.map(makeTimeline)
        }
        results += weightedLinesForRangeIngestions.compactMap { weightedLine in
            roaDuration.toFullRangeTimeline(
                nonNormalizedMaxOfRoute: nonNormalizedMaxOfRoute,
                areSubstanceHeightsIndependent: areSubstanceHeightsIndependent,
                graphStartTime: startGraph,
                weightedLine: weightedLine
            )
        }
        timelineDrawables = results
    }
    // swiftlint:enable function_body_length

    private static func getDistanceFromStartGraphInSeconds(graphStartTime: Date, time: Date) -> TimeInterval {
        time.timeIntervalSince1970 - graphStartTime.timeIntervalSince1970
    }

    func draw(
        context: GraphicsContext,
        height: Double,
        pixelsPerSec: Double,
        lineWidth: Double
    ) {
        for drawable in timelineDrawables {
            drawable.draw(
                context: context,
                height: height,
                pixelsPerSec: pixelsPerSec,
                color: color.swiftUIColor,
                lineWidth: lineWidth
            )
        }
    }
}
