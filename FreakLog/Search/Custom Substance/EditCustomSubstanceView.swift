import SwiftUI

struct EditCustomSubstanceView: View {
  @ObservedObject var customSubstance: CustomSubstance
  @Environment(\.dismiss) private var dismiss
  @State private var isShowingConfirmation = false
  @State private var units = ""
  @State private var name = ""
  @State private var description = ""

  private var trimmedName: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // Renaming onto another substance's name would merge their ingestions and data
  private var isNameTaken: Bool {
    guard trimmedName != customSubstance.nameUnwrapped else { return false }
    return SubstanceRepo.shared.getSubstance(name: trimmedName) != nil
      || PersistenceController.shared.getCustomSubstance(name: trimmedName) != nil
  }

  var body: some View {
    List {
      Section {
        TextField("Name", text: $name)
      } header: {
        Text("Name")
      } footer: {
        if isNameTaken {
          Text("Another substance is already called \(trimmedName). The name is kept as \(customSubstance.nameUnwrapped).")
            .foregroundColor(.red)
        } else {
          Text("Renaming also renames your ingestions, units and data of this substance.")
        }
      }
      Section("Description") {
        TextField("Description", text: $description)
      }
      Section("Units") {
        TextField("Units", text: $units)
      }
      Section {
        NavigationLink("Categories") {
          EditCategoriesScreen(substanceName: customSubstance.nameUnwrapped)
        }
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
        let name = customSubstance.nameUnwrapped
        PersistenceController.shared.viewContext.delete(customSubstance)
        // Its display name and categories go too, unless they belong to a PsychonautWiki substance of that name
        if SubstanceRepo.shared.getSubstance(name: name) == nil {
          PersistenceController.shared.setSubstanceOverride(for: name, displayName: nil, categories: nil)
        }
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
      let newName = trimmedName.isEmpty || isNameTaken ? oldName : trimmedName
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
