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

  private var results: [AnodyneIndexEntry] {
    guard entriesInstance == AnodyneSubstance.baseURL else { return [] }
    let text = searchText.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else { return entries }
    let matches = entries.filter { entry in
      ([entry.title] + entry.abbreviations + entry.classes).contains { $0.localizedStandardContains(text) }
    }
    // Names starting with the text first
    return matches.filter { isPrefixMatch($0, text) } + matches.filter { !isPrefixMatch($0, text) }
  }

  var body: some View {
    List {
      if isLoading {
        ProgressView()
          .frame(maxWidth: .infinity)
      } else if didFail {
        Button("Couldn't load AnodyneWiki. Try Again") {
          Task { await load() }
        }
      } else if results.isEmpty {
        Text("No AnodyneWiki substances match the search")
          .foregroundStyle(.secondary)
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
    .task(id: instanceURL) {
      await load()
    }
  }

  private func isPrefixMatch(_ entry: AnodyneIndexEntry, _ text: String) -> Bool {
    ([entry.title] + entry.abbreviations).contains { $0.lowercased().hasPrefix(text.lowercased()) }
  }

  // Selecting this source asks for its index once; filtering it uses the local copy
  private func load() async {
    let instance = AnodyneSubstance.baseURL
    entries = []
    entriesInstance = nil
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
    } catch {
      if !Task.isCancelled, instance == AnodyneSubstance.baseURL { didFail = true }
    }
  }
}
