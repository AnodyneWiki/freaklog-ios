import SwiftUI

struct CalendarColorRectangle: View {

    let colors: [Color]

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: colors),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
    }
}

#Preview {
    CalendarColorRectangle(colors: [.pink, .blue])
}
