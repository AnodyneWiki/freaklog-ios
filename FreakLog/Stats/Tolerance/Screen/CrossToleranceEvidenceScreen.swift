import SwiftUI

struct CrossToleranceEvidenceScreen: View {
    let confirmedDays: [SubstanceAndDay]

    private struct Study: Identifiable {
        let first: String
        let second: String
        let publication: String
        let url: URL

        var id: String { publication }
    }

    private let studies = [
        Study(first: "LSD", second: "Psilocybin", publication: "Isbell et al., 1961",
              url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/13717955/")!),
        Study(first: "LSD", second: "Mescaline", publication: "Wolbach et al., 1962",
              url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/14007904/")!)
    ]

    private func countDays(for name: String) -> Int {
        Set(confirmedDays.filter { $0.substanceName == name }.map { Calendar.current.startOfDay(for: $0.day) }).count
    }

    var body: some View {
        List {
            ForEach(studies) { study in
                let firstDays = countDays(for: study.first)
                let secondDays = countDays(for: study.second)
                Section {
                    LabeledContent(study.first, value: "\(firstDays) days")
                    LabeledContent(study.second, value: "\(secondDays) days")
                    if firstDays > 1 || secondDays > 1 {
                        Label("Repeated records with published overlap evidence", systemImage: "info.circle")
                    } else {
                        Text("Journal period has no repeated records for this pair.")
                            .foregroundStyle(.secondary)
                    }
                    Link(study.publication, destination: study.url)
                } header: {
                    Text("\(study.first) and \(study.second)")
                }
            }
            Section("About the Estimate") {
                Text("These human studies observed cross-tolerance after repeated administration. The journal highlights repeated records in the selected period and supports only the named study substances. It does not estimate how much tolerance you have, the amount of either substance with an equivalent effect, or when tolerance will wear off.")
            }
        }
        .navigationTitle("Cross-Tolerance")
    }
}
