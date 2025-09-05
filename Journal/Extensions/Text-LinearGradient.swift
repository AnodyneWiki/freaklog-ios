import SwiftUI

public extension Text {
    func foregroundLinearGradient(colors: [Color]) -> some View {
        overlay {
            LinearGradient(
                colors: colors,
                startPoint: .leading,
                endPoint: .trailing
            ).mask(
                self
            )
        }
    }
}
