import CoreData
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
          case .editProduct(let id):
            if let row = componentRows.first(where: { $0.id == id }), let layer = row.layer {
              IncludedProductAmountScreen(
                name: layer.name, unit: layer.unit, quantity: layer.quantity,
                scaledLeaves: { quantity in row.rescaled(to: quantity) }
              ) { leaves in
                values.components.replaceSubrange(row.range, with: leaves)
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
    .sheet(isPresented: $isAddingSavedProduct) {
      NavigationStack {
        FormulationProductPicker(parent: values) { leaves in
          values.components.append(contentsOf: leaves)
          isAddingSavedProduct = false
        }
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { isAddingSavedProduct = false }
          }
        }
      }
    }
  }

  private enum Destination: Hashable {
    case editComponent(id: UUID)
    case editProduct(id: UUID)
  }

  @Environment(\.dismiss) private var dismiss
  @State private var values: FormulationCodable
  @State private var path: [Destination] = []
  @State private var isShowingDeleteConfirmation = false
  @State private var isAddingComponent = false
  @State private var isAddingSavedProduct = false

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
        ForEach(componentRows) { row in
          if let layer = row.layer {
            NavigationLink(value: Destination.editProduct(id: row.id)) {
              VStack(alignment: .leading, spacing: 4) {
                Label(layer.name, systemImage: layer.kind == .formulation ? "square.stack" : "pills")
                Text("\(layer.quantity.formatted()) \(layer.unit)")
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
              }
            }
          } else if let component = row.leaves.first {
            NavigationLink(value: Destination.editComponent(id: component.id)) {
              FormulationComponentDoseRow(component: component)
            }
          }
        }
        .onDelete { offsets in
          var rows = componentRows
          rows.remove(atOffsets: offsets)
          values.components = rows.flatMap(\.leaves)
        }
        .onMove { source, destination in
          var rows = componentRows
          rows.move(fromOffsets: source, toOffset: destination)
          values.components = rows.flatMap(\.leaves)
        }
        Button {
          isAddingComponent = true
        } label: {
          Label("Add Substance", systemImage: "plus")
        }
        Button {
          isAddingSavedProduct = true
        } label: {
          Label("Add Saved Product", systemImage: "square.stack")
        }
      } header: {
        Text("Ingredients")
      } footer: {
        Text("Saved products retain a copy of their ingredients when added. Logging scales every ingredient by the amount taken.")
      }
      if let formulation {
        Section {
          JournalPresetShareLink(product: .formulation(formulation), title: "Share Saved Preset")
        }
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

  private var componentRows: [ComponentRow] {
    var rows: [ComponentRow] = []
    for (index, leaf) in values.components.enumerated() {
      if let layer = leaf.blendPath.first, let last = rows.indices.last, rows[last].layer == layer {
        rows[last].leaves.append(leaf)
        rows[last].range = rows[last].range.lowerBound..<(index + 1)
      } else {
        rows.append(ComponentRow(leaves: [leaf], range: index..<(index + 1)))
      }
    }
    return rows
  }

  private struct ComponentRow: Identifiable {
    var leaves: [FormulationCodable.Component]
    var range: Range<Int>
    var id: UUID { leaves[0].id }
    var layer: FormulationCodable.BlendLayer? { leaves.first?.blendPath.first }

    func rescaled(to quantity: Double) -> [FormulationCodable.Component]? {
      guard let layer, quantity.isFinite, quantity > 0 else { return nil }
      if quantity == layer.quantity { return leaves }
      let scaled = leaves.compactMap { leaf -> FormulationCodable.Component? in
        guard var leaf = leaf.scaled(by: quantity / layer.quantity) else { return nil }
        leaf.blendPath[0].quantity = quantity
        return leaf
      }
      return scaled.count == leaves.count ? scaled : nil
    }
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

private struct FormulationProductPicker: View {
  let parent: FormulationCodable
  let onAdd: ([FormulationCodable.Component]) -> Void

  @FetchRequest(fetchRequest: PersistenceController.formulationsRequest()) private var formulations: FetchedResults<Formulation>
  @FetchRequest(fetchRequest: PersistenceController.activeCustomUnitsRequest()) private var units: FetchedResults<CustomUnit>
  @State private var searchText = ""

  private var matchingFormulations: [Formulation] {
    formulations.filter { $0.matches(searchText: searchText) && parent.canInclude($0.includedProduct) }
  }

  private var matchingUnits: [CustomUnit] {
    units.filter {
      let unit = $0
      return (searchText.isEmpty || unit.nameUnwrapped.localizedCaseInsensitiveContains(searchText)
        || unit.substanceDisplayName.localizedCaseInsensitiveContains(searchText))
        && parent.canInclude(unit.includedProduct)
    }
  }

  var body: some View {
    List {
      if matchingFormulations.isEmpty, matchingUnits.isEmpty {
        Text(searchText.isEmpty ? "No saved products available to add." : "No matching saved products.")
          .foregroundStyle(.secondary)
      }
      if !matchingFormulations.isEmpty {
        Section("Formulations") {
          ForEach(matchingFormulations) { formulation in
            NavigationLink(value: formulation.includedProduct) {
              VStack(alignment: .leading, spacing: 4) {
                Text(formulation.nameUnwrapped)
                Text(formulation.componentsDescription).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
              }
            }
          }
        }
      }
      if !matchingUnits.isEmpty {
        Section("Custom Units") {
          ForEach(matchingUnits) { unit in
            NavigationLink(value: unit.includedProduct) {
              VStack(alignment: .leading, spacing: 4) {
                Text(unit.nameUnwrapped)
                Text(unit.doseOfOneUnitDescription).font(.subheadline).foregroundStyle(.secondary)
              }
            }
          }
        }
      }
    }
    .navigationTitle("Saved Products")
    .searchable(text: $searchText)
    .navigationDestination(for: FormulationCodable.IncludedProduct.self) { product in
      IncludedProductAmountScreen(name: product.name, unit: product.unit, quantity: 1,
                                  scaledLeaves: { product.leaves(quantity: $0) }, onDone: onAdd)
    }
  }
}

private struct IncludedProductAmountScreen: View {
  let name: String
  let unit: String
  let scaledLeaves: (Double) -> [FormulationCodable.Component]?
  let onDone: ([FormulationCodable.Component]) -> Void
  @State private var quantity: Double?

  init(name: String, unit: String, quantity: Double,
       scaledLeaves: @escaping (Double) -> [FormulationCodable.Component]?,
       onDone: @escaping ([FormulationCodable.Component]) -> Void) {
    self.name = name
    self.unit = unit
    self.scaledLeaves = scaledLeaves
    self.onDone = onDone
    _quantity = State(initialValue: quantity)
  }

  var body: some View {
    let preview = quantity.flatMap(scaledLeaves)
    Form {
      Section {
        LabeledContent("Amount") {
          TextField("Amount", value: $quantity, format: .number)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
          Text(unit)
            .foregroundStyle(.secondary)
        }
      } footer: {
        Text("These amounts will be included in one serving of the outer formulation.")
      }
      if let preview {
        Section("Included Ingredients") {
          ForEach(preview.indices, id: \.self) { index in
            FormulationComponentDoseRow(component: preview[index])
          }
        }
      }
    }
    .navigationTitle(name)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        DoneButton {
          if let preview { onDone(preview) }
        }
        .disabled(preview == nil)
      }
    }
  }
}

#Preview {
  EditFormulationScreen(formulation: .previewSample)
}
