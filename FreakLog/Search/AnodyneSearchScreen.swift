import SwiftUI
import WrappingHStack

// Searches all of AnodyneWiki's substances, including the many PsychonautWiki doesn't have
struct AnodyneSearchScreen: View {
  @State var searchText: String
  @State private var entries: [AnodyneIndexEntry] = []
  @State private var isLoading = true
  @State private var didFail = false

  private var results: [AnodyneIndexEntry] {
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
    .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
    .disableAutocorrection(true)
    .navigationTitle("AnodyneWiki")
    .task {
      await load()
    }
  }

  private func isPrefixMatch(_ entry: AnodyneIndexEntry, _ text: String) -> Bool {
    ([entry.title] + entry.abbreviations).contains { $0.lowercased().hasPrefix(text.lowercased()) }
  }

  // Opening the screen asks for AnodyneWiki's list, so it is loaded even without automatic loading
  private func load() async {
    isLoading = true
    didFail = false
    do {
      entries = try await AnodyneClient.shared.indexEntries()
    } catch {
      didFail = true
    }
    isLoading = false
  }
}
