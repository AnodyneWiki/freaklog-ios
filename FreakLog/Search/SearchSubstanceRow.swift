import SwiftUI
import WrappingHStack

struct SearchSubstanceRow: View {
    let substance: Substance

    var body: some View {
        NavigationLink(value: GlobalNavigationDestination.substance(substance: substance)) {
            VStack(alignment: .leading) {
                Text(substance.name).font(.headline)
                let commonNames = substance.commonNames.joined(separator: ", ")
                if !commonNames.isEmpty {
                    Text(commonNames).font(.subheadline).foregroundColor(.secondary)
                }
                Spacer().frame(height: 5)
                WrappingHStack(
                    alignment: .leading,
                    horizontalSpacing: 3,
                    verticalSpacing: 3
                ) {
                    ForEach(PersistenceController.shared.categories(for: substance.name), id: \.self) { category in
                        Chip(name: category)
                    }
                }
            }
        }
    }
}

struct Chip: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.caption)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(.systemGray5))
            .cornerRadius(12)
    }
}

#Preview {
    List {
        SearchSubstanceRow(substance: SubstanceRepo.shared.getSubstance(name: "MDMA")!)
    }.listStyle(.plain)
}
