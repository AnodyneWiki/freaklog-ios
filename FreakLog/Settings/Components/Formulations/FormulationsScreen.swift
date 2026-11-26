import CoreData
import SwiftUI

// MARK: - FormulationsScreen

struct FormulationsScreen: View {

  var body: some View {
    List {
      if filteredFormulations.isEmpty {
        Text(formulations.isEmpty ? "No formulations" : "No Results")
          .foregroundColor(.secondary)
      }
      ForEach(filteredFormulations) { formulation in
        Button {
          sheetToShow = .edit(formulation)
        } label: {
          FormulationRow(formulation: formulation).foregroundColor(.primary)
        }
      }
      .onDelete { offsets in
        deletionCandidates = offsets.map { filteredFormulations[$0] }
        confirmsDeletion = true
      }
    }
    .listStyle(.plain)
    .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          sheetToShow = .add
        } label: {
          Label("Add Formulation", systemImage: "plus").labelStyle(.iconOnly)
        }
      }
    }
    .sheet(item: $sheetToShow) { sheet in
      switch sheet {
      case .add:
        EditFormulationScreen(formulation: nil)
      case .edit(let formulation):
        EditFormulationScreen(formulation: formulation)
      }
    }
    .navigationTitle("Formulations")
    .confirmationDialog(
      deletionCandidates.count == 1 ? "Delete Formulation?" : "Delete Formulations?",
      isPresented: $confirmsDeletion,
      titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive, action: deleteSelectedFormulations)
    }
    .alert("Couldn’t Delete Formulations", isPresented: $showsDeletionError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("Your formulations are still saved. Try again.")
    }
  }

  private enum SheetOption: Identifiable {
    case add
    case edit(Formulation)

    var id: AnyHashable {
      switch self {
      case .add: "add"
      case .edit(let formulation): formulation.objectID
      }
    }
  }

  @FetchRequest(fetchRequest: PersistenceController.formulationsRequest())
  private var formulations: FetchedResults<Formulation>

  @State private var searchText = ""
  @State private var sheetToShow: SheetOption?
  @State private var deletionCandidates: [Formulation] = []
  @State private var confirmsDeletion = false
  @State private var showsDeletionError = false

  private var filteredFormulations: [Formulation] {
    formulations.filter { $0.matches(searchText: searchText) }
  }

  private func deleteSelectedFormulations() {
    do {
      let context = try PersistenceController.shared.journalEditContext()
      let objects = try deletionCandidates.map { try PersistenceController.journalObject($0, in: context) }
      objects.forEach(context.delete)
      try PersistenceController.saveJournalChanges(in: context)
    } catch {
      showsDeletionError = true
    }
    deletionCandidates = []
  }
}

// MARK: - FormulationRow

struct FormulationRow: View {
  @ObservedObject var formulation: Formulation

  var body: some View {
    VStack(alignment: .leading) {
      Text(formulation.nameUnwrapped).font(.headline)
      Text(formulation.componentsDescription)
        .font(.subheadline)
        .foregroundColor(.secondary)
      if !formulation.noteUnwrapped.isEmpty {
        Text(formulation.noteUnwrapped)
      }
    }
  }
}

#Preview {
  NavigationStack {
    FormulationsScreen()
  }
  .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
