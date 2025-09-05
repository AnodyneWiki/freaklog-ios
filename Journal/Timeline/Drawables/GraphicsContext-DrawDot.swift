import SwiftUI

extension GraphicsContext {
    func drawDot(x: Double, bottomY: Double, color: Color) {
        let dotRadius: CGFloat = 7
        let dotWidth = dotRadius * 2
        fill(
            Path(ellipseIn: CGRect(x: x - dotRadius, y: bottomY - dotRadius, width: dotWidth, height: dotWidth)),
            with: .color(color)
        )
    }
}
