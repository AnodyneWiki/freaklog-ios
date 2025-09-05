import SwiftUI

struct FabLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            let circleWidth: Double = 54
            Circle()
                .fill(Color.accentColor)
                .frame(width: circleWidth, height: circleWidth)
                .shadow(color: Color.black.opacity(0.3), radius: 3, x: 3, y: 3)
            Label(configuration)
                .labelStyle(.iconOnly)
                .font(.title.weight(.semibold))
                .foregroundColor(.white)
        }
    }
}

#Preview {
    Button {
    } label: {
        Label("New Ingestion", systemImage: "plus").labelStyle(FabLabelStyle())
    }
}
