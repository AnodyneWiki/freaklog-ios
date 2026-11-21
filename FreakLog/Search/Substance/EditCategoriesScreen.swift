import SwiftUI

// Picks the categories of a substance. They are saved as the user's own only while they differ from
// PsychonautWiki's (custom substances have none to start from).
struct EditCategoriesScreen: View {
  let substanceName: String
  @State private var selection: [String] = []
  @FetchRequest private var overrides: FetchedResults<SubstanceOverride>

  init(substanceName: String) {
    self.substanceName = substanceName
    let request = PersistenceController.substanceOverridesRequest()
    request.predicate = NSPredicate(format: "substanceName == %@", substanceName)
    _overrides = FetchRequest(fetchRequest: request)
  }

  private var psychonautWikiCategories: [String] {
    SubstanceRepo.shared.getSubstance(name: substanceName)?.categories ?? []
  }

  var body: some View {
    List {
      Section {
        ForEach(SubstanceRepo.shared.categories, id: \.name) { category in
          Button {
            toggle(category.name)
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(category.name.localizedCapitalized)
                  .foregroundColor(.primary)
                Text(category.description)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(2)
              }
              Spacer()
              if selection.contains(category.name) {
                Image(systemName: "checkmark")
                  .foregroundColor(.accentColor)
              }
            }
          }
        }
      } footer: {
        Text(
          "Categories are used by the search filters and to warn about interactions with whole groups, "
            + "such as stimulants or opioids."
        )
      }
      if overrides.first?.categoryList != nil, !psychonautWikiCategories.isEmpty {
        Section {
          Button("Reset to PsychonautWiki Categories", role: .destructive) {
            selection = psychonautWikiCategories
            save()
          }
        }
      }
    }
    .navigationTitle("Categories")
    .onAppear {
      selection = PersistenceController.shared.categories(for: substanceName)
    }
  }

  // Keeps the order of the category list
  private func toggle(_ name: String) {
    let selected = selection.contains(name) ? selection.filter { $0 != name } : selection + [name]
    selection = SubstanceRepo.shared.categories.map(\.name).filter(selected.contains)
    save()
  }

  private func save() {
    let isDefault = Set(selection) == Set(psychonautWikiCategories)
    PersistenceController.shared.setSubstanceOverride(
      for: substanceName,
      displayName: overrides.first?.displayName,
      categories: isDefault ? nil : selection
    )
  }
}

#Preview {
  NavigationStack {
    EditCategoriesScreen(substanceName: "MDMA")
  }
}
