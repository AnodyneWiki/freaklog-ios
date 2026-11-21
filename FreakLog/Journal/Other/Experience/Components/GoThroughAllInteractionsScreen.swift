import SwiftUI

struct GoThroughAllInteractionsScreen: View {
    let substancesToCheck: [Substance]

    var body: some View {
        List {
            ForEach(substancesToCheck) { substance in
                Section(substance.displayName) {
                    if let interactions = substance.interactions {
                        InteractionsGroup(
                            interactions: interactions,
                            substance: substance
                        )
                    } else {
                        Text("No documented interactions")
                    }
                }
            }
        }.navigationTitle("Interactions")
    }
}

#Preview {
    NavigationStack {
        GoThroughAllInteractionsScreen(
            substancesToCheck: Array(SubstanceRepo.shared.substances.prefix(5))
        )
    }
}
