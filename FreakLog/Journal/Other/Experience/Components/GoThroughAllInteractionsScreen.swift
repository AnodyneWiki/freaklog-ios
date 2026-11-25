import SwiftUI

struct GoThroughAllInteractionsScreen: View {
    let substancesToCheck: [Substance]
    var detected: [Interaction] = []

    var body: some View {
        List {
            if !detected.isEmpty {
                Section("Detected Pairs") {
                    ForEach(detected) { interaction in
                        NavigationLink(value: GlobalNavigationDestination.interactionPair(interaction)) {
                            InteractionPairRow(
                                aName: interaction.aName,
                                bName: interaction.bName,
                                interactionType: interaction.interactionType
                            )
                        }
                    }
                }
            }
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

struct InteractionPairDetailScreen: View {
    let interaction: Interaction

    private var classification: LocalizedStringKey {
        switch interaction.interactionType {
        case .uncertain: "Uncertain"
        case .unsafe: "Unsafe"
        case .dangerous: "Dangerous"
        }
    }

    var body: some View {
        let sources = InteractionChecker.documentedSources(for: interaction)
        List {
            Section {
                LabeledContent("Substance", value: PersistenceController.shared.displayName(for: interaction.aName))
                LabeledContent("Substance", value: PersistenceController.shared.displayName(for: interaction.bName))
                LabeledContent {
                    Text(classification).foregroundStyle(interaction.interactionType.color)
                } label: {
                    Text("Reference Classification")
                }
            }
            if !sources.isEmpty {
                Section("Sources") {
                    ForEach(sources) { source in
                        if let article = source.url,
                           let url = URL(string: "#Dangerous_interactions", relativeTo: article)?.absoluteURL {
                            NavigationLink(value: GlobalNavigationDestination.webViewInteractions(
                                substanceName: source.name, articleURL: url
                            )) {
                                Text(source.displayName)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Interaction")
    }
}

#Preview {
    NavigationStack {
        GoThroughAllInteractionsScreen(
            substancesToCheck: Array(SubstanceRepo.shared.substances.prefix(5))
        )
    }
}
