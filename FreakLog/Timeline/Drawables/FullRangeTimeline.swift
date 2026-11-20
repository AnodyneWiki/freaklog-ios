import SwiftUI

struct FullRangeTimeline: TimelineDrawable {
    let onset: FullDurationRange
    let comeup: FullDurationRange
    let peak: FullDurationRange
    let offset: FullDurationRange
    let nonNormalizedMaxOfRoute: Double
    let areSubstanceHeightsIndependent: Bool
    let points: [FullCumulativeTimelines.Point]

    init(
        onset: FullDurationRange,
        comeup: FullDurationRange,
        peak: FullDurationRange,
        offset: FullDurationRange,
        nonNormalizedMaxOfRoute: Double,
        areSubstanceHeightsIndependent: Bool,
        graphStartTime: Date,
        weightedLine: WeightedLine,
        nonNormalizedOverallMax: Double = 1.0
    ) {
        self.onset = onset
        self.comeup = comeup
        self.peak = peak
        self.offset = offset
        self.nonNormalizedMaxOfRoute = nonNormalizedMaxOfRoute
        self.areSubstanceHeightsIndependent = areSubstanceHeightsIndependent
        self.nonNormalizedOverallMax = nonNormalizedOverallMax
        let points = FullCumulativeTimelines.getSamplePointsFrom(
            graphStartTime: graphStartTime,
            weightedLine: weightedLine,
            onset: onset,
            comeup: comeup,
            peak: peak,
            offset: offset
        )
        self.points = points
    }

    var nonNormalizedHeight: Double {
        points.map { $0.y }.max() ?? 1
    }

    var nonNormalizedOverallMax = 1.0


    var endOfLineRelativeToStartInSeconds: TimeInterval {
        points.last?.x ?? 10
    }

    func draw(
        context: GraphicsContext,
        height: Double,
        pixelsPerSec: Double,
        color: Color,
        lineWidth: Double
    ) {
        let halfLineWidth = lineWidth / 2
        let paddingTop = halfLineWidth
        let paddingBottom = halfLineWidth
        let heightBetween = height - paddingTop - paddingBottom
        guard let firstPoint = points.first else { return }
        var path = Path()
        let maxPointHeight = points.map({$0.y}).max() ?? 1
        let nonNormalizedMax = areSubstanceHeightsIndependent ? maxPointHeight : nonNormalizedOverallMax
        let firstHeightInPx = firstPoint.y/nonNormalizedMax * heightBetween + paddingBottom
        path.move(to: CGPoint(x: firstPoint.x * pixelsPerSec, y: height - firstHeightInPx))
        for point in points.dropFirst() {
            let heightInPx = point.y/nonNormalizedMax * heightBetween + paddingBottom
            path.addLine(to: CGPoint(x: point.x * pixelsPerSec, y: height - heightInPx))
        }
        context.stroke(path, with: .color(color), style: StrokeStyle.getNormal(lineWidth: lineWidth))
        // draw shape
        guard let lastX = points.last?.x else { return }
        path.addLine(to: CGPoint(x: lastX * pixelsPerSec, y: height))
        path.addLine(to: CGPoint(x: firstPoint.x * pixelsPerSec, y: height))
        path.closeSubpath()
        context.fill(path, with: .color(color.opacity(shapeOpacity)))
    }
}

extension RoaDuration {
    func toFullRangeTimeline(
        nonNormalizedMaxOfRoute: Double,
        areSubstanceHeightsIndependent: Bool,
        graphStartTime: Date,
        weightedLine: WeightedLine
    ) -> FullRangeTimeline? {
        if let fullOnset = onset?.maybeFullDurationRange,
           let fullComeup = comeup?.maybeFullDurationRange,
           let fullPeak = peak?.maybeFullDurationRange,
           let fullOffset = offset?.maybeFullDurationRange {
            return FullRangeTimeline(
                onset: fullOnset,
                comeup: fullComeup,
                peak: fullPeak,
                offset: fullOffset,
                nonNormalizedMaxOfRoute: nonNormalizedMaxOfRoute,
                areSubstanceHeightsIndependent: areSubstanceHeightsIndependent,
                graphStartTime: graphStartTime,
                weightedLine: weightedLine
            )
        } else {
            return nil
        }
    }
}
