import SwiftUI

struct AcknowledgeSaferUseScreen: View {
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

    private var nextLink: some View {
        NavigationLink(value: AddIngestionDestination.interactions(substance: substance)) {
            NextLabel()
        }
    }

    var screen: some View {
        List {
            Section {
                ForEach(substance.saferUse, id: \.self) { point in
                    Text(point)
                }
            }
        }.navigationTitle("Safer \(substance.displayName)")
    }
}

#Preview {
    NavigationStack {
        AcknowledgeSaferUseScreen(substance: SubstanceRepo.shared.getSubstance(name: "MDMA")!, dismiss: {})
    }
}
