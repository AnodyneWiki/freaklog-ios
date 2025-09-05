import SwiftUI

extension View {
    func colorBackground(_ substanceColor: SubstanceColor) -> some View {
        modifier(ColorBackground(substanceColor: substanceColor))
    }
}

struct ColorBackground: ViewModifier {
    let substanceColor: SubstanceColor

    func body(content: Content) -> some View {
        content
            .padding(5)
            .background(substanceColor.swiftUIColor.opacity(shapeOpacity))
            .cornerRadius(8)
    }
}
