import SwiftUI

struct SubstanceBox: View {
    let substance: Substance
    let dismiss: () -> Void
    let isEyeOpen: Bool

    var body: some View {
        if isEyeOpen {
            if !substance.saferUse.isEmpty {
                NavigationLink(value: AddIngestionDestination.saferUse(substance: substance)) {
                    content
                }.overlay(alignment: .bottom) {
                    Divider()
                }
            } else {
                NavigationLink(value: AddIngestionDestination.interactions(substance: substance)) {
                    content
                }.overlay(alignment: .bottom) {
                    Divider()
                }
            }
        } else {
            NavigationLink(value: SubstanceAndRoute(
                substance: .psychonautWiki(substance),
                administrationRoute: .oral
            )) {
                content
            }.overlay(alignment: .bottom) {
                Divider()
            }
        }
    }

    private var content: some View {
        NavigatableListItemContent(title: substance.displayName) {
            if !substance.commonNames.isEmpty {
                Text(substance.commonNames, format: .list(type: .or))
            }
        }
    }
}

#Preview {
    NavigationStack {
        LazyVStack {
            SubstanceBox(
                substance: SubstanceRepo.shared.getSubstance(name: "MDMA")!,
                dismiss: {},
                isEyeOpen: true
            )
        }
    }
}
