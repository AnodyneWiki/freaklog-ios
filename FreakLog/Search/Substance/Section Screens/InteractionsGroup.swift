import SwiftUI

// MARK: - InteractionsGroup

struct InteractionsGroup: View {
    let interactions: Interactions
    let substance: Substance

    var body: some View {
        Group {
            ForEach(interactions.dangerous, id: \.self) { name in
                LinkOrLabel(substance: substance) {
                    HStack {
                        Text(name)
                        Spacer()
                        DangerTriangles(interactionType: .dangerous)
                    }.foregroundColor(InteractionType.dangerous.color)
                }
            }
            ForEach(interactions.unsafe, id: \.self) { name in
                LinkOrLabel(substance: substance) {
                    HStack {
                        Text(name)
                        Spacer()
                        DangerTriangles(interactionType: .unsafe)
                    }.foregroundColor(InteractionType.unsafe.color)
                }
            }
            ForEach(interactions.uncertain, id: \.self) { name in
                LinkOrLabel(substance: substance) {
                    HStack {
                        Text(name)
                        Spacer()
                        DangerTriangles(interactionType: .uncertain)
                    }.foregroundColor(InteractionType.uncertain.color)
                }
            }
        }
    }
}

// MARK: - LinkOrLabel

private struct LinkOrLabel<Label: View>: View {

    let substance: Substance
    let label: () -> Label

    var body: some View {
        if let url = substance.url,
           let interactionURL = URL(string: url.absoluteString + "#Dangerous_interactions") {
            NavigationLink(value: GlobalNavigationDestination.webViewInteractions(substanceName: substance.name, articleURL: interactionURL)) {
                label()
            }
        } else {
            label()
        }
    }
}

private let substance = SubstanceRepo.shared.getSubstance(name: "MDMA")!
#Preview {
    List {
        Section {
            InteractionsGroup(
                interactions: substance.interactions!,
                substance: substance)
        }
    }
}
