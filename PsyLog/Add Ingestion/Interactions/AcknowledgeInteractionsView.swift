import SwiftUI

struct AcknowledgeInteractionsView: View {
    let substance: Substance
    let dismiss: () -> Void

    var body: some View {
        AcknowledgeInteractionsContent(
            substance: substance,
            dismiss: dismiss
        )
    }
}

struct AcknowledgeInteractionsContent: View {
    let substance: Substance
    let dismiss: () -> Void

    var body: some View {
        screen.toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                nextLink
            }
        }
    }

    private var screen: some View {
        List {
            if let interactions = substance.interactions {
                InteractionsGroup(
                    interactions: interactions,
                    substance: substance
                )
            } else {
                Text("There are no documented interactions")
            }
        }
        .navigationBarTitle(substance.name + " Interactions")
    }

    private var nextLink: some View {
        NavigationLink(value: ChooseRouteScreenArguments(substance: substance)) {
            NextLabel()
        }
    }
}

#Preview {
    NavigationStack {
        AcknowledgeInteractionsContent(
            substance: SubstanceRepo.shared.getSubstance(name: "MDMA")!,
            dismiss: {}
        )
    }
}
