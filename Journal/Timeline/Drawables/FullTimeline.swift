import SwiftUI

struct FullTimeline: TimelineDrawable {
    let onset: FullDurationRange
    let comeup: FullDurationRange
    let peak: FullDurationRange
    let offset: FullDurationRange
    let peakAndOffsetWeight: Double
    let nonNormalizedHeight: Double
    let nonNormalizedMaxOfRoute: Double
    let areSubstanceHeightsIndependent: Bool
    let onsetDelayInHours: Double
    let ingestionTimeRelativeToStartInSeconds: TimeInterval

    var nonNormalizedOverallMax = 1.0
    private var normalizedHeight: Double {
        if areSubstanceHeightsIndependent {
            nonNormalizedHeight/nonNormalizedMaxOfRoute
        } else {
            nonNormalizedHeight/nonNormalizedOverallMax
        }
    }

    private let onsetComeupWeight = 0.5

    var endOfLineRelativeToStartInSeconds: TimeInterval {
        ingestionTimeRelativeToStartInSeconds
            + onsetDelayInSeconds
            + onset.interpolateLinearly(at: onsetComeupWeight)
            + comeup.interpolateLinearly(at: onsetComeupWeight)
            + peak.interpolateLinearly(at: peakAndOffsetWeight)
            + offset.interpolateLinearly(at: peakAndOffsetWeight)
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
        let startX = ingestionTimeRelativeToStartInSeconds * pixelsPerSec
        var top = lineWidth / 2
        if normalizedHeight < 1 {
            top = (1 - normalizedHeight) * heightBetween
        }
        let bottom = height - paddingTop
        var path = Path()
        path.move(to: CGPoint(x: startX, y: bottom))
        let onsetEndX = startX + (onsetDelayInSeconds + onset.interpolateLinearly(at: onsetComeupWeight)) * pixelsPerSec
        path.addLine(to: CGPoint(x: onsetEndX, y: bottom))
        let comeupEndX = onsetEndX + (comeup.interpolateLinearly(at: onsetComeupWeight) * pixelsPerSec)
        path.addLine(to: CGPoint(x: comeupEndX, y: top))
        let peakEndX = comeupEndX + (peak.interpolateLinearly(at: peakAndOffsetWeight) * pixelsPerSec)
        path.addLine(to: CGPoint(x: peakEndX, y: top))
        let offsetEndX = peakEndX + (offset.interpolateLinearly(at: peakAndOffsetWeight) * pixelsPerSec)
        path.addLine(to: CGPoint(x: offsetEndX, y: bottom))
        context.stroke(path, with: .color(color), style: StrokeStyle.getNormal(lineWidth: lineWidth))
        path.addLine(to: CGPoint(x: offsetEndX, y: height))
        path.addLine(to: CGPoint(x: startX, y: height))
        path.closeSubpath()
        context.fill(path, with: .color(color.opacity(shapeOpacity)))
        context.drawDot(x: startX, bottomY: bottom, color: color)
    }

    private var onsetDelayInSeconds: TimeInterval {
        onsetDelayInHours * 60 * 60
    }
}

extension RoaDuration {
    func toFullTimeline(
        peakAndOffsetWeight: Double,
        nonNormalizedHeight: Double,
        nonNormalizedMaxOfRoute: Double,
        areSubstanceHeightsIndependent: Bool,
        onsetDelayInHours: Double,
        ingestionTimeRelativeToStartInSeconds: TimeInterval
    ) -> FullTimeline? {
        if let fullOnset = onset?.maybeFullDurationRange,
           let fullComeup = comeup?.maybeFullDurationRange,
           let fullPeak = peak?.maybeFullDurationRange,
           let fullOffset = offset?.maybeFullDurationRange {
            return FullTimeline(
                onset: fullOnset,
                comeup: fullComeup,
                peak: fullPeak,
                offset: fullOffset,
                peakAndOffsetWeight: peakAndOffsetWeight,
                nonNormalizedHeight: nonNormalizedHeight,
                nonNormalizedMaxOfRoute: nonNormalizedMaxOfRoute,
                areSubstanceHeightsIndependent: areSubstanceHeightsIndependent,
                onsetDelayInHours: onsetDelayInHours,
                ingestionTimeRelativeToStartInSeconds: ingestionTimeRelativeToStartInSeconds
            )
        } else {
            return nil
        }
    }
}
