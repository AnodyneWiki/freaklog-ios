import SwiftUI

struct SubstanceScreen: View {
    let substance: Substance

    @State private var isShowingAddIngestionSheet = false

    var body: some View {
        List {
            if !substance.isApproved {
                Section {
                    Text("Info Not PW Approved")
                }
            }
            Group {
                Group { // group is here because we cannot have more than 10 subviews
                    if let summary = substance.summary {
                        Section("Summary") {
                            VStack {
                                Text(summary)
                                if !substance.categories.isEmpty {
                                    CategorySection(substance: substance)
                                }
                            }
                        }
                    } else {
                        if !substance.categories.isEmpty {
                            Section("Categories") {
                                CategorySection(substance: substance)
                            }
                        }
                    }
                    if let effects = substance.effectsSummary {
                        Section("Effects") {
                            Text(effects)
                        }
                    }
                }
                Group {
                    if substance.dosageRemark != nil || !substance.doseInfos.isEmpty {
                        DosesSection(substance: substance)
                    }
                    let durationInfos = substance.durationInfos
                    if !durationInfos.isEmpty {
                        DurationSection(substance: substance)
                    }
                    if let interactions = substance.interactions {
                        Section("Interactions") {
                            InteractionsGroup(
                                interactions: interactions,
                                substance: substance
                            )
                        }
                    }
                    if substance.tolerance != nil || !substance.crossTolerances.isEmpty {
                        ToleranceSection(substance: substance)
                    }
                    if !substance.toxicities.isEmpty {
                        ToxicitySection(substance: substance)
                    }
                }
                Group {
                    if let acute = substance.generalRisks {
                        Section("Acute Risk") {
                            Text(acute)
                        }
                    }
                    if let longTerm = substance.longtermRisks {
                        Section("Long-term Risk") {
                            Text(longTerm)
                        }
                    }
                    if !substance.saferUse.isEmpty {
                        Section("Safer Use") {
                            ForEach(substance.saferUse, id: \.self) { point in
                                Text(point)
                            }
                        }
                    }
                    if let addictionPotential = substance.addictionPotential {
                        Section("Addiction Potential") {
                            Text(addictionPotential)
                        }
                    }
                }
            }

        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Article", value: GlobalNavigationDestination.webView(articleURL: substance.url))
            }
        }
        .fullScreenCover(isPresented: $isShowingAddIngestionSheet) {
            NavigationStack {
                AcknowledgeInteractionsView(substance: substance) {
                    isShowingAddIngestionSheet.toggle()
                }
            }
        }
        .navigationTitle(substance.name)
    }
}

#Preview {
    NavigationStack {
        SubstanceScreen(
            substance: SubstanceRepo.shared.getSubstance(name: "MDMA")!
        )
    }
}
