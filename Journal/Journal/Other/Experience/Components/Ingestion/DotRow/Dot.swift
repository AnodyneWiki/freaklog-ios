import SwiftUI

struct Dot: View {
    let isFull: Bool

    var body: some View {
        Image(systemName: isFull ? "circle.fill" : "circle")
            .font(.caption2)
    }
}

#Preview {
    Dot(isFull: true)
}
