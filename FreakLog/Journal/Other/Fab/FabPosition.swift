import SwiftUI

struct FabPosition<Screen: View, Button: View>: View {
    @ViewBuilder let button: Button
    @ViewBuilder let screen: Screen
    let alignment: Alignment

    init(alignment: Alignment = .bottom, @ViewBuilder button: () -> Button, @ViewBuilder screen: () -> Screen) {
        self.alignment = alignment
        self.button = button()
        self.screen = screen()
    }

    var body: some View {
        ZStack(alignment: alignment) {
            screen
            button.padding(20)
        }
    }
}

#Preview {
    FabPosition(alignment: .bottomTrailing) {
        Button {} label: {
            Label("New Ingestion", systemImage: "plus")
                .labelStyle(FabLabelStyle())
        }
    } screen: {
        Color.gray.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
