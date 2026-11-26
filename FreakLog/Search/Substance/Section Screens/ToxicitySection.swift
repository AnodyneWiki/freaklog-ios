import SwiftUI

// PsychonautWiki's toxicity notes and AnodyneWiki's reported fatal doses and overdose treatment
struct ToxicitySection: View {
    let substance: Substance?
    var anodyne: AnodyneSubstance?

    var body: some View {
        let toxicities = substance?.toxicities ?? []
        if !toxicities.isEmpty || anodyne?.reportedFatalDose != nil || anodyne?.treatment != nil {
            Section("Toxicity") {
                ForEach(toxicities, id: \.self) { toxicity in
                    Text(toxicity)
                }
                if let url = substance?.url, !toxicities.isEmpty,
                   let toxicityURL = URL(string: url.absoluteString + "#Toxicity_and_harm_potential") {
                    NavigationLink(value: GlobalNavigationDestination.webView(articleURL: toxicityURL)) {
                        Label("More Info", systemImage: "info.circle")
                    }
                }
                if let fatalDose = anodyne?.reportedFatalDose {
                    ExpandableText(title: "Reported Fatal Doses", text: fatalDose)
                }
                if let treatment = anodyne?.treatment {
                    ExpandableText(title: "Treatment of Overdose", text: treatment)
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
