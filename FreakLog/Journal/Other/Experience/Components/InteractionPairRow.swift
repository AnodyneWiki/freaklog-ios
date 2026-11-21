import SwiftUI

struct InteractionPairRow: View {
    let aName: String
    let bName: String
    let interactionType: InteractionType

    var body: some View {
        HStack(spacing: 0) {
            Text(PersistenceController.shared.displayName(for: aName)).lineLimit(1)
            Spacer()
            Image(systemName: "arrow.left.arrow.right")
            Spacer()
            Text(PersistenceController.shared.displayName(for: bName)).lineLimit(1)
            Spacer()
            ForEach(0 ..< interactionType.dangerCount, id: \.self) { _ in
                Image(systemName: "exclamationmark.triangle")
            }
        }.foregroundColor(interactionType.color)
    }
}

#Preview {
    List {
        InteractionPairRow(
            aName: "Amphetamine with a long name",
            bName: "Tramadol",
            interactionType: .dangerous
        )
    }
}
