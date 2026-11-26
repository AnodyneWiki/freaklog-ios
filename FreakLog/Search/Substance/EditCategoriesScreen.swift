import CoreData
import SwiftUI

// Picks the categories of a substance. They are saved as the user's own only while they differ from
// the bundled catalog defaults (custom substances have none to start from).
struct EditCategoriesScreen: View {
  let substanceName: String
  @State private var selection: [String] = []
  // Redraws the screen when the user's name or categories for the substance change
  @FetchRequest private var overrides: FetchedResults<SubstanceOverride>

  init(substanceName: String) {
    self.substanceName = substanceName
    _overrides = FetchRequest(fetchRequest: PersistenceController.substanceOverridesRequest(for: substanceName))
  }

  private var override: SubstanceOverrideCache.Entry? {
    PersistenceController.shared.substanceOverride(for: substanceName)
  }

  private var defaultCategories: [String] {
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
      if override?.categories != nil, !defaultCategories.isEmpty {
        Section {
          Button("Reset to Default Categories", role: .destructive) {
            selection = defaultCategories
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

  // Appends new categories, so the original order with the drug class first survives
  private func toggle(_ name: String) {
    selection = selection.contains(name) ? selection.filter { $0 != name } : selection + [name]
    save()
  }

  private func save() {
    let isDefault = Set(selection) == Set(defaultCategories)
    PersistenceController.shared.setSubstanceOverride(
      for: substanceName,
      displayName: override?.displayName,
      categories: isDefault ? nil : selection
    )
  }
}

#Preview {
  NavigationStack {
    EditCategoriesScreen(substanceName: "MDMA")
  }
}
