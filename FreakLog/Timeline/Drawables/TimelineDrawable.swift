import SwiftUI

protocol TimelineDrawable {
    func draw(
        context: GraphicsContext,
        height: Double,
        pixelsPerSec: Double,
        color: Color,
        lineWidth: Double
    )

    var endOfLineRelativeToStartInSeconds: TimeInterval { get }
    var nonNormalizedHeight: Double { get }
    var nonNormalizedOverallMax: Double { get set }
}
