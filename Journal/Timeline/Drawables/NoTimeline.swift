import Foundation
import SwiftUI

struct NoTimeline: TimelineDrawable {
    let nonNormalizedHeight = 0.01 // low number because if this turns out to be max of timeline then it will be used as overall max which will downsize ingestions with timelines
    let onsetDelayInHours: Double
    let ingestionTimeRelativeToStartInSeconds: TimeInterval

    var nonNormalizedOverallMax = 1.0

    var endOfLineRelativeToStartInSeconds: TimeInterval {
        ingestionTimeRelativeToStartInSeconds + onsetDelayInSeconds
    }

    private var onsetDelayInSeconds: TimeInterval {
        onsetDelayInHours * 60 * 60
    }

    func draw(
        context: GraphicsContext,
        height: Double,
        pixelsPerSec: Double,
        color: Color,
        lineWidth: Double
    ) {
        let startX = ingestionTimeRelativeToStartInSeconds * pixelsPerSec
        let halfLineWidth = lineWidth / 2
        context.drawDot(x: startX, bottomY: height - halfLineWidth, color: color)
        if onsetDelayInHours > 0 {
            let maxHeight = height - halfLineWidth
            let onsetEndX = startX + onsetDelayInSeconds * pixelsPerSec
            var path = Path()
            path.move(to: CGPoint(x: startX, y: maxHeight))
            path.addLine(to: CGPoint(x: onsetEndX, y: maxHeight))
            context.stroke(path, with: .color(color), style: StrokeStyle.getNormal(lineWidth: lineWidth))
        }
    }
}
