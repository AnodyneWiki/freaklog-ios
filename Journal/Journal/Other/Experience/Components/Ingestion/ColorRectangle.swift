import SwiftUI

struct ColorRectangle: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 6)
            .padding(.vertical, 8)
    }
}

#Preview {
    ColorRectangle(color: .blue)
}
