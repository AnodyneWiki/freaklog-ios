import SwiftUI

struct FabPosition<Screen: View, Button: View>: View {
    @ViewBuilder let button: Button
    @ViewBuilder let screen: Screen

    var body: some View {
        ZStack(alignment: .bottom) {
            screen
            button.padding(20)
        }
    }
}

#Preview {
    FabPosition {
        Button {} label: {
            Label("New Ingestion", systemImage: "plus")
                .labelStyle(FabLabelStyle())
        }
    } screen: {
        Color.gray.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
