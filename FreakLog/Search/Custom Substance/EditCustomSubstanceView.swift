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
      Section {
        CustomRoaRouteList(substanceName: customSubstance.nameUnwrapped, customSubstance: customSubstance)
      } header: {
        Text("Routes (Dose & Duration)")
      } footer: {
        Text("Add dose ranges and timing data per administration route.")
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
      guard !units.isEmpty else { return }
      let oldName = customSubstance.nameUnwrapped
      let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
      let newName = trimmed.isEmpty ? oldName : trimmed
      customSubstance.name = newName
      customSubstance.units = units
      customSubstance.explanation = description
      if newName != oldName {
        PersistenceController.shared.renameSubstance(from: oldName, to: newName)
      }
      PersistenceController.shared.saveViewContext()
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
