import SwiftUI

struct ToleranceTextsScreen: View {
    let substances: [SubstanceWithToleranceAndColor]

    var body: some View {
        List {
            ForEach(substances) { substance in
                Section {
                    if let full = substance.full {
                        RowLabelView(label: "full", value: full)
                    }
                    if let half = substance.half {
                        RowLabelView(label: "half", value: half)
                    }
                    if let zero = substance.zero {
                        RowLabelView(label: "zero", value: zero)
                    }
                    let crossTolerances = substance.crossTolerances.joined(separator: ", ")
                    if !crossTolerances.isEmpty {
                        Text("Cross tolerance with \(crossTolerances)")
                    }
                } header: {
                    HStack {
                        Image(systemName: "circle.fill").foregroundColor(substance.color.swiftUIColor)
                        Text(substance.substanceName)
                    }
                }
            }
        }
        .navigationTitle("Tolerances")
        .toolbar {
            NavigationLink(value: GlobalNavigationDestination.toleranceChartExplanation) {
                Label("Chart Limitations", systemImage: "info.circle")
                    .labelStyle(.titleOnly)
            }
        }
    }
}

#Preview {
    NavigationStack {
        let substances = Array(SubstanceRepo.shared.substances.filter { sub in
            guard let tolerance = sub.tolerance else { return false }
            return tolerance.halfToleranceInHours != nil && tolerance.zeroToleranceInHours != nil
        }.shuffled().prefix(5))
        let substancsWith = substances.map { sub in
            sub.toSubstanceWithToleranceAndColor(substanceColor: SubstanceColor.allCases.randomElement() ?? .red)
        }
        ToleranceTextsScreen(substances: substancsWith)
    }
}
