import SwiftUI

struct TimedNoteDrawable {
    let distanceFromStart: TimeInterval

    private let color: SubstanceColor

    init(
        startGraph: Date,
        time: Date,
        color: SubstanceColor
    ) {
        self.color = color
        distanceFromStart = time.timeIntervalSinceReferenceDate - startGraph.timeIntervalSinceReferenceDate
    }

    func draw(
        context: GraphicsContext,
        height: Double,
        pixelsPerSec: Double,
        lineWidth: Double
    ) {
        let halfLineWidth = lineWidth / 2
        let x = (distanceFromStart * pixelsPerSec) + halfLineWidth
        var path = Path()
        path.move(to: CGPoint(x: x, y: height))
        path.addLine(to: CGPoint(x: x, y: 0))
        context.stroke(
            path,
            with: .color(color.swiftUIColor),
            style: StrokeStyle.getTimedNoteStokeStyle()
        )
    }
}
