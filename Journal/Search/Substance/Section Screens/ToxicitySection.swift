import SwiftUI

struct ToxicitySection: View {

    let substance: Substance

    var body: some View {
        Section("Toxicity") {
            ForEach(substance.toxicities, id: \.self) { toxicity in
                Text(toxicity)
            }
            if let toxicityURL = URL(string: substance.url.absoluteString + "#Toxicity_and_harm_potential") {
                NavigationLink(value: GlobalNavigationDestination.webView(articleURL: toxicityURL)) {
                    Label("More Info", systemImage: "info.circle")
                }
            }
        }
    }
}

#Preview {
    List {
        ToxicitySection(
            substance: SubstanceRepo.shared.getSubstance(name: "LSD")!
        )
    }
}
