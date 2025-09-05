import SwiftUI

struct RatingDrawable {
    let distanceFromStart: TimeInterval

    private let option: ShulginRatingOption

    init(
        startGraph: Date,
        time: Date,
        option: ShulginRatingOption
    ) {
        self.option = option
        distanceFromStart = time.timeIntervalSinceReferenceDate - startGraph.timeIntervalSinceReferenceDate
    }

    func draw(
        context: inout GraphicsContext,
        height: Double,
        pixelsPerSec: Double,
        lineWidth: Double
    ) {
        let halfLineWidth = lineWidth / 2
        let x = (distanceFromStart * pixelsPerSec) + halfLineWidth
        var path = Path()
        path.move(to: CGPoint(x: x, y: 0))
        let halfHeight = height / 2
        let padding: Double = 25
        path.addLine(to: CGPoint(x: x, y: halfHeight - padding))
        switch option {
        case .minus, .plusMinus, .plus:
            context.draw(
                Text(option.stringRepresentation).foregroundColor(.gray),
                at: CGPoint(x: x, y: halfHeight),
                anchor: .center
            )
        case .twoPlus, .threePlus, .fourPlus:
            context.rotate(by: .degrees(90))
            context.draw(
                Text(option.stringRepresentation).foregroundColor(.gray),
                at: CGPoint(x: halfHeight, y: -x - halfLineWidth / 2),
                anchor: .center
            )
            context.rotate(by: .degrees(-90))
        }
        path.move(to: CGPoint(x: x, y: halfHeight + padding))
        path.addLine(to: CGPoint(x: x, y: height))
        context.stroke(path, with: .color(.gray), lineWidth: 2)
    }
}
