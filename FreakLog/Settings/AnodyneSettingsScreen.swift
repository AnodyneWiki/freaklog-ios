import SwiftUI

struct AnodyneSettingsScreen: View {
  @AppStorage(PersistenceController.isAnodyneAutoLoadEnabledKey) private var isAutoLoadEnabled = false
  @State private var cacheSize: Int64 = 0

  var body: some View {
    List {
      Section {
        Toggle("Load Automatically", isOn: $isAutoLoadEnabled)
          .tint(.accentColor)
      } footer: {
        Text(
          "Substance pages then load AnodyneWiki's data as they open. Otherwise it is only loaded when you tap "
            + "Load from AnodyneWiki. Each load tells anodyne.wiki which substance you looked at; "
            + "loaded data is kept on this device for a week."
        )
      }
      Section {
        Button("Delete Downloaded Data", role: .destructive) {
          Task {
            await AnodyneClient.shared.clearCache()
            cacheSize = await AnodyneClient.shared.cacheSize()
          }
        }
        .disabled(cacheSize == 0)
      } footer: {
        Text("\(ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file)) downloaded")
      }
      Section {
        NavigationLink(value: GlobalNavigationDestination.anodyneSearch(query: "")) {
          Label("Browse AnodyneWiki", systemImage: "magnifyingglass")
        }
        NavigationLink(value: GlobalNavigationDestination.webView(articleURL: AnodyneSubstance.baseURL)) {
          Label("anodyne.wiki", systemImage: "books.vertical")
        }
      } footer: {
        Text(
          "AnodyneWiki is a meta-wiki that aggregates substance data from many sources. Its content is in the public "
            + "domain unless noted otherwise. Its dose tiers are derived from logged doses via DBI-IGS and are not "
            + "recommendations."
        )
      }
    }
    .navigationTitle("AnodyneWiki")
    .task {
      cacheSize = await AnodyneClient.shared.cacheSize()
    }
  }
}
