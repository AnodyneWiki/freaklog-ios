import SwiftUI

// MARK: - EditFormulationScreen

// Edits a saved formulation or returns a draft for the calling form to save.
struct EditFormulationScreen: View {

  init(formulation: Formulation?) {
    self.formulation = formulation
    self.onDraft = nil
    _values = State(initialValue: formulation.map(FormulationCodable.init) ?? FormulationCodable(
      name: "",
      note: "",
      creationDate: .now,
      components: []))
  }

  init(draft: FormulationCodable, onDraft: @escaping (FormulationCodable) -> Void) {
    self.formulation = nil
    self.onDraft = onDraft
    _values = State(initialValue: draft)
  }

  let formulation: Formulation?
  private let onDraft: ((FormulationCodable) -> Void)?
  @State private var isShowingSaveError = false

  var body: some View {
    NavigationStack(path: $path) {
      form
        .alert("Couldn't save formulation changes", isPresented: $isShowingSaveError) {
          Button("OK", role: .cancel) {}
        }
        .navigationTitle(formulation == nil ? "Add Formulation" : "Edit Formulation")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
              dismiss()
            }
          }
          ToolbarItem(placement: .primaryAction) {
            DoneButton(action: save)
              .disabled(!canSave)
          }
        }
        .navigationDestination(for: Destination.self) { destination in
          switch destination {
          case .editComponent(let id):
            if let index = values.components.firstIndex(where: { $0.id == id }) {
              let component = values.components[index]
              EditFormulationComponentScreen(
                substance: AddIngestionSubstance(storedName: component.substanceName, units: component.units),
                component: component)
              { editedComponent in
                values.components[index] = editedComponent
                path.removeAll()
              }
            }
          }
        }
    }
    // A sheet of its own, because popping past the searchable substance list in one go sometimes did nothing
    .sheet(isPresented: $isAddingComponent) {
      NavigationStack {
        SubstancePickerList { $0 }
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Cancel") {
                isAddingComponent = false
              }
            }
          }
          .navigationDestination(for: AddIngestionSubstance.self) { substance in
            EditFormulationComponentScreen(substance: substance, component: nil) { component in
              values.components.append(component)
              isAddingComponent = false
            }
          }
      }
    }
  }

  private enum Destination: Hashable {
    case editComponent(id: UUID)
  }

  @Environment(\.dismiss) private var dismiss
  @State private var values: FormulationCodable
  @State private var path: [Destination] = []
  @State private var isShowingDeleteConfirmation = false
  @State private var isAddingComponent = false

  private var canSave: Bool {
    !values.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !values.components.isEmpty
  }

  private var form: some View {
    Form {
      Section {
        TextField("Name", text: $values.name, prompt: Text("e.g. Party pill, Speedball"))
          .textInputAutocapitalization(.sentences)
          .autocorrectionDisabled()
        TextField("Notes", text: $values.note, axis: .vertical)
      }
      Section {
        ForEach(values.components) { component in
          NavigationLink(value: Destination.editComponent(id: component.id)) {
            FormulationComponentDoseRow(component: component)
          }
        }
        .onDelete { offsets in
          values.components.remove(atOffsets: offsets)
        }
        .onMove { source, destination in
          values.components.move(fromOffsets: source, toOffset: destination)
        }
        Button {
          isAddingComponent = true
        } label: {
          Label("Add Substance", systemImage: "plus")
        }
      } header: {
        Text("Substances")
      } footer: {
        Text("Logging a formulation adds an ingestion of each substance with these doses, multiplied by the amount taken.")
      }
      if let formulation {
        Section {
          Button(role: .destructive) {
            isShowingDeleteConfirmation = true
          } label: {
            Label("Delete Formulation", systemImage: "trash").foregroundColor(.red)
          }
          .confirmationDialog(
            "Delete \(formulation.nameUnwrapped)?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible)
          {
            Button("Delete", role: .destructive) {
              delete(formulation)
            }
            Button("Cancel", role: .cancel) { }
          } message: {
            Text("Ingestions logged with it are kept.")
          }
        }
      }
    }
    .scrollDismissesKeyboard(.interactively)
  }

  private func save() {
    var trimmed = values
    trimmed.name = values.name.trimmingCharacters(in: .whitespacesAndNewlines)
    if let onDraft {
      onDraft(trimmed)
      dismiss()
      return
    }

    do {
      let context = try PersistenceController.shared.journalEditContext()
      if let formulation {
        trimmed.apply(to: try PersistenceController.journalObject(formulation, in: context))
      } else {
        trimmed.insert(into: context)
      }
      try context.save()
      dismiss()
    } catch {
      isShowingSaveError = true
    }
  }

  private func delete(_ formulation: Formulation) {
    do {
      let context = try PersistenceController.shared.journalEditContext()
      context.delete(try PersistenceController.journalObject(formulation, in: context))
      try context.save()
      dismiss()
    } catch {
      isShowingSaveError = true
    }
  }
}

#Preview {
  EditFormulationScreen(formulation: .previewSample)
}
