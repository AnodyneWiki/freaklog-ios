import SwiftUI

struct ExperienceColorRectangle: View {
    let colors: [Color]

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: colors),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 10)
            .padding(.vertical, 8)
    }
}

#Preview {
    ExperienceColorRectangle(colors: [.pink, .blue])
}
