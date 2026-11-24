import SwiftUI

struct FabLabelStyle: LabelStyle {
    // A smaller, quieter button for an action next to the main one
    var isSecondary = false

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            let circleWidth: Double = isSecondary ? 40 : 54
            Circle()
                .fill(isSecondary ? Color(.secondarySystemBackground) : Color.accentColor)
                .frame(width: circleWidth, height: circleWidth)
                .shadow(color: Color.black.opacity(0.3), radius: 3, x: 3, y: 3)
            Label(configuration)
                .labelStyle(.iconOnly)
                .font(isSecondary ? .title3.weight(.semibold) : .title.weight(.semibold))
                .foregroundColor(isSecondary ? .accentColor : .white)
        }
        // Keeps the smaller button at the minimum tap target
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Circle())
    }
}

// The add button of the journal: tapping adds an ingestion, holding adds a timed note
struct AddFabButton: View {
    let addIngestion: () -> Void
    let addTimedNote: () -> Void

    @State private var isPressed = false

    var body: some View {
        Label("New Ingestion", systemImage: "plus")
            .labelStyle(FabLabelStyle())
            .scaleEffect(isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.15), value: isPressed)
            .onTapGesture(perform: addIngestion)
            .onLongPressGesture(minimumDuration: 0.4) {
                playHapticFeedback()
                addTimedNote()
            } onPressingChanged: { isPressing in
                isPressed = isPressing
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { addIngestion() }
            .accessibilityAction(named: "Add Timed Note") { addTimedNote() }
    }
}

#Preview {
    Button {
    } label: {
        Label("New Ingestion", systemImage: "plus").labelStyle(FabLabelStyle())
    }
}
