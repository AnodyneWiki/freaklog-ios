import Foundation
import SwiftUI

struct OnsetComeupTimeline: TimelineDrawable {
    let onset: FullDurationRange
    let comeup: FullDurationRange
    let onsetDelayInHours: Double
    let nonNormalizedHeight: Double
    let nonNormalizedMaxOfRoute: Double
    let areSubstanceHeightsIndependent: Bool
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
        ingestionTimeRelativeToStartInSeconds + onsetDelayInSeconds + onset.interpolateLinearly(at: onsetComeupWeight) + comeup.interpolateLinearly(at: onsetComeupWeight)
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
        let bottom = height - lineWidth / 2
        context.drawDot(x: startX, bottomY: bottom, color: color)
        let onsetEndX = startX + (onsetDelayInSeconds + onset.interpolateLinearly(at: onsetComeupWeight)) * pixelsPerSec
        let comeupEndX = onsetEndX + (comeup.interpolateLinearly(at: onsetComeupWeight) * pixelsPerSec)
        var path = Path()
        path.move(to: CGPoint(x: startX, y: bottom))
        path.addLine(to: CGPoint(x: onsetEndX, y: bottom))
        path.addLine(to: CGPoint(x: comeupEndX, y: top))
        context.stroke(path, with: .color(color), style: StrokeStyle.getNormal(lineWidth: lineWidth))
        path.addLine(to: CGPoint(x: comeupEndX, y: height))
        path.addLine(to: CGPoint(x: startX, y: height))
        path.closeSubpath()
        context.fill(path, with: .color(color.opacity(shapeOpacity)))
    }

    private var onsetDelayInSeconds: TimeInterval {
        onsetDelayInHours * 60 * 60
    }
}

extension RoaDuration {
    func toOnsetComeupTimeline(
        nonNormalizedHeight: Double,
        nonNormalizedMaxOfRoute: Double,
        areSubstanceHeightsIndependent: Bool,
        onsetDelayInHours: Double,
        ingestionTimeRelativeToStartInSeconds: TimeInterval
    ) -> OnsetComeupTimeline? {
        if let fullOnset = onset?.maybeFullDurationRange,
           let fullComeup = comeup?.maybeFullDurationRange {
            return OnsetComeupTimeline(
                onset: fullOnset,
                comeup: fullComeup,
                onsetDelayInHours: onsetDelayInHours,
                nonNormalizedHeight: nonNormalizedHeight,
                nonNormalizedMaxOfRoute: nonNormalizedMaxOfRoute,
                areSubstanceHeightsIndependent: areSubstanceHeightsIndependent,
                ingestionTimeRelativeToStartInSeconds: ingestionTimeRelativeToStartInSeconds
            )
        } else {
            return nil
        }
    }
}
