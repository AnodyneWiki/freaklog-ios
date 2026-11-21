import SwiftUI

struct AddToleranceIngestionScreen: View {
    @StateObject private var viewModel = ChooseSubstanceScreen.ViewModel()
    @Environment(\.dismiss) var dismiss
    let finish: (SubstanceAndDay) -> Void

    var body: some View {
        NavigationStack {
            List(viewModel.filteredSubstances, id: \.name) { substance in
                if substance.tolerance?.halfToleranceInHours != nil || substance.tolerance?.zeroToleranceInHours != nil {
                    NavigationLink {
                        ChooseDateScreen(substanceName: substance.name,
                                         cancel: { dismiss() },
                                         finish: finish)
                    } label: {
                        Text(substance.displayName)
                            .font(.headline)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text(substance.displayName)
                            .font(.headline)
                        Spacer()
                        Text("No tolerance info")
                    }.foregroundColor(.secondary)
                }
            }
            .listStyle(.plain)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .navigationTitle("Add Temp. Ingestion")
            .scrollDismissesKeyboard(.interactively)
            .searchable(text: $viewModel.searchText, prompt: "Search substance")
            .disableAutocorrection(true)
        }
    }
}
