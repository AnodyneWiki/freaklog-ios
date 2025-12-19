import SwiftUI

struct DangerTriangles: View {
    let interactionType: InteractionType
    private let iconName = "exclamationmark.triangle"

    var body: some View {
        HStack(spacing: 0) {
            switch interactionType {
            case .uncertain:
                Image(systemName: iconName)
            case .unsafe:
                Image(systemName: iconName)
                Image(systemName: iconName)
            case .dangerous:
                Image(systemName: iconName)
                Image(systemName: iconName)
                Image(systemName: iconName)
            }
        }.foregroundColor(interactionType.color)
    }
}

#Preview {
    DangerTriangles(interactionType: .dangerous)
}
