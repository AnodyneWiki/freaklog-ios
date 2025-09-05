import SwiftUI

struct EditCustomSubstanceView: View {
    @ObservedObject var customSubstance: CustomSubstance
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingConfirmation = false
    @State private var units = ""
    @State private var name = ""
    @State private var description = ""

    var body: some View {
        List {
            Section("Name") {
                TextField("Name", text: $name)
            }
            Section("Description") {
                TextField("Description", text: $description)
            }
            Section("Units") {
                TextField("Units", text: $units)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .confirmationDialog(
            "Are you sure you want to delete this substance?",
            isPresented: $isShowingConfirmation
        ) {
            Button("Delete Substance", role: .destructive) {
                dismiss()
                PersistenceController.shared.viewContext.delete(customSubstance)
                PersistenceController.shared.saveViewContext()
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            name = customSubstance.nameUnwrapped
            units = customSubstance.unitsUnwrapped
            description = customSubstance.explanationUnwrapped
        }
        .onDisappear {
            if !units.isEmpty {
                customSubstance.name = name
                customSubstance.units = units
                customSubstance.explanation = description
                PersistenceController.shared.saveViewContext()
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    isShowingConfirmation.toggle()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle(customSubstance.nameUnwrapped)
    }
}
