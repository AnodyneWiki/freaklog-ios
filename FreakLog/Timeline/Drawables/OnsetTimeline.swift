import Foundation
import SwiftUI

struct OnsetTimeline: TimelineDrawable {
    let nonNormalizedHeight = 1.0

    let onset: FullDurationRange
    let onsetDelayInHours: Double
    let ingestionTimeRelativeToStartInSeconds: TimeInterval

    var nonNormalizedOverallMax = 1.0

    private let onsetAndComeupWeight = 0.5

    private var onsetDelayInSeconds: TimeInterval {
        onsetDelayInHours * 60 * 60
    }

    var endOfLineRelativeToStartInSeconds: TimeInterval {
        ingestionTimeRelativeToStartInSeconds + onsetDelayInHours * 60 * 60 + onset.interpolateLinearly(at: onsetAndComeupWeight)
    }

    func draw(
        context: GraphicsContext,
        height: Double,
        pixelsPerSec: Double,
        color: Color,
        lineWidth: Double
    ) {
        let startX = ingestionTimeRelativeToStartInSeconds * pixelsPerSec
        let minHeight = lineWidth / 2
        let maxHeight = height - minHeight
        context.drawDot(x: startX, bottomY: maxHeight, color: color)
        let onsetEndX = startX + (onsetDelayInSeconds + onset.interpolateLinearly(at: onsetAndComeupWeight)) * pixelsPerSec
        var path = Path()
        path.move(to: CGPoint(x: startX, y: maxHeight))
        path.addLine(to: CGPoint(x: onsetEndX, y: maxHeight))
        context.stroke(path, with: .color(color), style: StrokeStyle.getNormal(lineWidth: lineWidth))
    }
}

extension RoaDuration {
    func toOnsetTimeline(
        onsetDelayInHours: Double,
        ingestionTimeRelativeToStartInSeconds: TimeInterval
    ) -> OnsetTimeline? {
        if let fullOnset = onset?.maybeFullDurationRange {
            return OnsetTimeline(
                onset: fullOnset,
                onsetDelayInHours: onsetDelayInHours,
                ingestionTimeRelativeToStartInSeconds: ingestionTimeRelativeToStartInSeconds
            )
        } else {
            return nil
        }
    }
}
