import SwiftUI
import WrappingHStack

// Searches all of AnodyneWiki's substances, including the many PsychonautWiki doesn't have
struct AnodyneSearchScreen: View {
  @State var searchText: String

  var body: some View {
    AnodyneSearchResults(searchText: searchText)
      .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search AnodyneWiki")
      .disableAutocorrection(true)
      .navigationTitle("AnodyneWiki")
      .navigationBarTitleDisplayMode(.inline)
  }
}

struct AnodyneSearchResults: View {
  let searchText: String
  @AppStorage(PersistenceController.anodyneInstanceURLKey) private var instanceURL = ""
  @State private var entries: [AnodyneIndexEntry] = []
  @State private var entriesInstance: URL?
  @State private var isLoading = true
  @State private var didFail = false
  @State private var selectedClasses: Set<String> = []
  @State private var showsFilters = false

  private var results: [AnodyneIndexEntry] {
    guard entriesInstance == AnodyneSubstance.baseURL else { return [] }
    return AnodyneIndexEntry.search(entries, text: searchText, classKeys: selectedClasses)
  }

  var body: some View {
    let results = results
    List {
      if isLoading {
        ProgressView()
          .frame(maxWidth: .infinity)
      } else if didFail {
        Button("Couldn't load AnodyneWiki. Try Again") {
          Task { await load() }
        }
      } else if results.isEmpty {
        if selectedClasses.isEmpty {
          Text("No AnodyneWiki substances match the search")
            .foregroundStyle(.secondary)
        } else {
          Text("No substances match the search and selected classes.")
            .foregroundStyle(.secondary)
          Button("Clear Filters") { selectedClasses.removeAll() }
        }
      }
      ForEach(results) { entry in
        NavigationLink(value: GlobalNavigationDestination.anodyneSubstance(title: entry.title)) {
          VStack(alignment: .leading, spacing: 4) {
            Text(entry.title)
              .font(.headline)
            if !entry.abbreviations.isEmpty {
              Text(entry.abbreviations.joined(separator: ", "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            if !entry.classes.isEmpty {
              WrappingHStack(alignment: .leading, horizontalSpacing: 3, verticalSpacing: 3) {
                ForEach(entry.classes, id: \.self) { substanceClass in
                  Chip(name: substanceClass)
                }
              }
            }
          }
        }
      }
    }
    .listStyle(.plain)
    .scrollDismissesKeyboard(.interactively)
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button {
          showsFilters = true
        } label: {
          Label("Search Filters", systemImage: selectedClasses.isEmpty
                ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityValue(Text("\(selectedClasses.count) classes selected"))
        .disabled(isLoading || didFail || !entries.contains { !$0.classes.isEmpty })
      }
    }
    .sheet(isPresented: $showsFilters) {
      AnodyneClassFilters(
        classes: AnodyneIndexEntry.classOptions(in: entries),
        selection: $selectedClasses
      )
    }
    .task(id: instanceURL) {
      await load()
    }
  }

  // Selecting this source asks for its index once; filtering it uses the local copy
  private func load() async {
    let instance = AnodyneSubstance.baseURL
    if entriesInstance != instance {
      selectedClasses.removeAll()
      showsFilters = false
      entriesInstance = nil
    }
    entries = []
    isLoading = true
    didFail = false
    defer {
      if !Task.isCancelled, instance == AnodyneSubstance.baseURL { isLoading = false }
    }
    let client = AnodyneClient.shared
    let context = await client.requestContext()
    guard !Task.isCancelled, context.baseURL == instance else { return }
    do {
      let result = try await client.indexEntries(using: context)
      guard await client.isCurrent(context), !Task.isCancelled, instance == AnodyneSubstance.baseURL else { return }
      entriesInstance = instance
      entries = result
      selectedClasses.formIntersection(Set(AnodyneIndexEntry.classOptions(in: result).map(AnodyneIndexEntry.classKey)))
    } catch {
      if !Task.isCancelled, instance == AnodyneSubstance.baseURL { didFail = true }
    }
  }
}

private struct AnodyneClassFilters: View {
  let classes: [String]
  @Binding var selection: Set<String>
  @State private var draft: Set<String>
  @State private var query = ""
  @Environment(\.dismiss) private var dismiss

  init(classes: [String], selection: Binding<Set<String>>) {
    self.classes = classes
    self._selection = selection
    self._draft = State(initialValue: selection.wrappedValue)
  }

  var body: some View {
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let matches = text.isEmpty ? classes : classes.filter { $0.localizedStandardContains(text) }
    NavigationStack {
      List {
        Section {
          if matches.isEmpty {
            Text("No matching classes").foregroundStyle(.secondary)
          }
          ForEach(matches, id: \.self) { name in
            let key = AnodyneIndexEntry.classKey(name)
            let isSelected = draft.contains(key)
            Button {
              if isSelected { draft.remove(key) } else { draft.insert(key) }
            } label: {
              HStack {
                Text(name).foregroundStyle(.primary)
                Spacer()
                if isSelected {
                  Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
          }
        } footer: {
          Text("Show substances in any of the selected classes.")
        }
      }
      .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a class")
      .disableAutocorrection(true)
      .navigationTitle("Substance Classes")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            selection = draft
            dismiss()
          }
        }
        ToolbarItem(placement: .bottomBar) {
          Button("Clear Selection") { draft.removeAll() }
            .disabled(draft.isEmpty)
        }
      }
    }
  }
}
