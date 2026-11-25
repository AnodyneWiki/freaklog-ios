import SwiftUI

struct UnifiedSearchFilters {
    enum JournalType: CaseIterable {
        case all, experiences, ingestions

        var title: String {
            switch self {
            case .all: String(localized: "All Entries")
            case .experiences: String(localized: "Experiences")
            case .ingestions: String(localized: "Ingestions")
            }
        }
    }

    enum LibraryType: CaseIterable {
        case all, bundled, custom

        var title: String {
            switch self {
            case .all: String(localized: "All Substances")
            case .bundled: String(localized: "Bundled Substances")
            case .custom: String(localized: "Custom Substances")
            }
        }
    }

    var journalType = JournalType.all
    var ingestionKind = UnifiedJournalQuery.IngestionKind.any
    var libraryType = LibraryType.all
    var categories: Set<String> = []
    var personalTag: String?
    var untaggedOnly = false

    var libraryIsFiltered: Bool {
        libraryType != .all || !categories.isEmpty || personalTag != nil || untaggedOnly
    }

    mutating func clearLibrary() {
        libraryType = .all
        categories.removeAll()
        personalTag = nil
        untaggedOnly = false
    }
}

struct UnifiedSearchFilterScreen: View {
    let scope: UnifiedSearchScope
    @Binding var filters: UnifiedSearchFilters
    @Binding var favoritesOnly: Bool
    let categories: [String]
    let tags: [String]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if scope.includesJournal {
                    Section("Journal") {
                        Picker("Result Type", selection: $filters.journalType) {
                            ForEach(UnifiedSearchFilters.JournalType.allCases, id: \.self) { type in
                                Text(type.title).tag(type)
                            }
                        }
                        Picker("Logged As", selection: $filters.ingestionKind) {
                            ForEach(UnifiedJournalQuery.IngestionKind.allCases, id: \.self) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        Toggle("Favorite Experiences Only", isOn: $favoritesOnly)
                    }
                }
                if scope.includesLibrary {
                    Section("Library") {
                        Picker("Result Type", selection: $filters.libraryType) {
                            ForEach(UnifiedSearchFilters.LibraryType.allCases, id: \.self) { type in
                                Text(type.title).tag(type)
                            }
                        }
                        NavigationLink {
                            List {
                                ForEach(categories, id: \.self) { category in
                                    Toggle(category.localizedCapitalized, isOn: categoryBinding(category))
                                }
                            }
                            .navigationTitle("Categories")
                        } label: {
                            LabeledContent("Categories", value: filters.categories.isEmpty
                                           ? String(localized: "All") : filters.categories.count.formatted())
                        }
                        Toggle("Untagged Only", isOn: $filters.untaggedOnly)
                            .onChange(of: filters.untaggedOnly) { isUntagged in
                                if isUntagged { filters.personalTag = nil }
                            }
                        if !tags.isEmpty && !filters.untaggedOnly {
                            Picker("Personal Tag", selection: $filters.personalTag) {
                                Text("All Tags").tag(nil as String?)
                                ForEach(tags, id: \.self) { tag in
                                    Text(tag).tag(Optional(tag))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Search Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func categoryBinding(_ category: String) -> Binding<Bool> {
        Binding(get: { filters.categories.contains(category) }, set: { isSelected in
            if isSelected { filters.categories.insert(category) }
            else { filters.categories.remove(category) }
        })
    }
}
