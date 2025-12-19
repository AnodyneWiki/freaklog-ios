import SwiftUI

struct ToleranceSection: View {
    let substance: Substance

    var body: some View {
        Section {
            if let full = substance.tolerance?.full {
                RowLabelView(label: "full", value: full)
            }
            if let half = substance.tolerance?.half {
                RowLabelView(label: "half", value: half)
            }
            if let zero = substance.tolerance?.zero {
                RowLabelView(label: "zero", value: zero)
            }
            let crossTolerances = substance.crossTolerances.joined(separator: ", ")
            if !crossTolerances.isEmpty {
                Text("Cross tolerance with \(crossTolerances)")
            }
        } header: {
            Text("Tolerance")
        } footer: {
            Text("* zero is the time to no tolerance")
        }

    }
}

#Preview {
    List {
        ToleranceSection(substance: SubstanceRepo.shared.getSubstance(name: "Amphetamine")!)
    }
}
