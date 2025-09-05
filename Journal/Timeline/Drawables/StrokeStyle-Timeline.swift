import SwiftUI

extension StrokeStyle {
    static func getNormal(lineWidth: CGFloat) -> StrokeStyle {
        return StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
    }

    static func getDotted(lineWidth: CGFloat) -> StrokeStyle {
        return StrokeStyle(
            lineWidth: lineWidth,
            lineCap: .round,
            lineJoin: .round,
            dash: [10, 10],
            dashPhase: 0
        )
    }

    static let timedNoteLineWidth: Double = 3

    static func getTimedNoteStokeStyle() -> StrokeStyle {
        return StrokeStyle(
            lineWidth: timedNoteLineWidth,
            lineCap: .round,
            lineJoin: .round,
            dash: [5, 8],
            dashPhase: 0
        )
    }
}
