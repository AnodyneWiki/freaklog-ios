import SwiftUI

struct OnsetComeupPeakTimeline: TimelineDrawable {
    let onset: FullDurationRange
    let comeup: FullDurationRange
    let peak: FullDurationRange
    let peakWeight: Double
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

    private let onsetAndComeupWeight = 0.5

    var endOfLineRelativeToStartInSeconds: TimeInterval {
        ingestionTimeRelativeToStartInSeconds
            + onsetDelayInSeconds
            + onset.interpolateLinearly(at: onsetAndComeupWeight)
            + comeup.interpolateLinearly(at: onsetAndComeupWeight)
            + peak.interpolateLinearly(at: peakWeight)
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
        context.drawDot(x: startX, bottomY: bottom, color: color)
        let onsetEndX = startX + (onsetDelayInSeconds + onset.interpolateLinearly(at: onsetAndComeupWeight)) * pixelsPerSec
        let comeupEndX = onsetEndX + (comeup.interpolateLinearly(at: onsetAndComeupWeight) * pixelsPerSec)
        let peakEndX = comeupEndX + (peak.interpolateLinearly(at: peakWeight) * pixelsPerSec)
        var path = Path()
        path.move(to: CGPoint(x: startX, y: bottom))
        path.addLine(to: CGPoint(x: onsetEndX, y: bottom))
        path.addLine(to: CGPoint(x: comeupEndX, y: top))
        path.addLine(to: CGPoint(x: peakEndX, y: top))
        context.stroke(path, with: .color(color), style: StrokeStyle.getNormal(lineWidth: lineWidth))
        path.addLine(to: CGPoint(x: peakEndX, y: height))
        path.addLine(to: CGPoint(x: startX, y: height))
        path.closeSubpath()
        context.fill(path, with: .color(color.opacity(shapeOpacity)))
    }

    private var onsetDelayInSeconds: TimeInterval {
        onsetDelayInHours * 60 * 60
    }
}

extension RoaDuration {
    func toOnsetComeupPeakTimeline(
        peakWeight: Double,
        nonNormalizedHeight: Double,
        nonNormalizedMaxOfRoute: Double,
        areSubstanceHeightsIndependent: Bool,
        onsetDelayInHours: Double,
        ingestionTimeRelativeToStartInSeconds: TimeInterval
    ) -> OnsetComeupPeakTimeline? {
        if let fullOnset = onset?.maybeFullDurationRange,
           let fullComeup = comeup?.maybeFullDurationRange,
           let fullPeak = peak?.maybeFullDurationRange {
            return OnsetComeupPeakTimeline(
                onset: fullOnset,
                comeup: fullComeup,
                peak: fullPeak,
                peakWeight: peakWeight,
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
