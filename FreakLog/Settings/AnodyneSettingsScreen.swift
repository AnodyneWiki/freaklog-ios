import SwiftUI

struct AnodyneSettingsScreen: View {
  @AppStorage(PersistenceController.isAnodyneAutoLoadEnabledKey) private var isAutoLoadEnabled = false
  // Empty for the default instance
  @AppStorage(PersistenceController.anodyneInstanceURLKey) private var instanceURL = ""
  @State private var draftInstanceURL = ""
  @FocusState private var isEditingInstanceURL: Bool
  @State private var cacheSize: Int64 = 0

  private var host: String {
    AnodyneSubstance.baseURL.host() ?? "AnodyneWiki"
  }

  private var isDraftInvalid: Bool {
    let draft = draftInstanceURL.trimmingCharacters(in: .whitespacesAndNewlines)
    return !draft.isEmpty && AnodyneSubstance.instanceURL(from: draft) == nil
  }

  var body: some View {
    List {
      Section {
        Toggle("Load Automatically", isOn: $isAutoLoadEnabled)
          .tint(.accentColor)
      } footer: {
        Text(
          "Substance pages then load AnodyneWiki's data as they open. Otherwise it is only loaded when you tap "
            + "More from AnodyneWiki. Each load tells \(host) which substance you looked at; "
            + "loaded data is kept on this device for a week."
        )
      }
      Section {
        TextField(AnodyneSubstance.defaultBaseURL.absoluteString, text: $draftInstanceURL)
          .keyboardType(.URL)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .submitLabel(.done)
          .focused($isEditingInstanceURL)
          .onSubmit(applyInstanceURL)
        if !instanceURL.isEmpty {
          Button("Use \(AnodyneSubstance.defaultBaseURL.host() ?? "anodyne.wiki")") {
            draftInstanceURL = ""
            applyInstanceURL()
          }
        }
      } header: {
        Text("Instance")
      } footer: {
        if isDraftInvalid {
          Text("Enter a web address, such as wiki.example.org.")
            .foregroundColor(.red)
        } else {
          Text(
            "The AnodyneWiki to load data from and link to. Changing it deletes the data downloaded from the "
              + "previous one."
          )
        }
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
          Label(host, systemImage: "books.vertical")
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
    .onAppear {
      draftInstanceURL = instanceURL
    }
    .onChange(of: isEditingInstanceURL) { isEditing in
      if !isEditing {
        applyInstanceURL()
      }
    }
    .onDisappear(perform: applyInstanceURL)
    .task {
      cacheSize = await AnodyneClient.shared.cacheSize()
    }
  }

  // Stores a valid address (none for the default instance) and drops the data loaded from the previous one.
  // An invalid one stays in the field, marked, until it is corrected.
  private func applyInstanceURL() {
    let draft = draftInstanceURL.trimmingCharacters(in: .whitespacesAndNewlines)
    let newValue: String
    if draft.isEmpty {
      newValue = ""
    } else if let url = AnodyneSubstance.instanceURL(from: draft) {
      newValue = url == AnodyneSubstance.defaultBaseURL ? "" : url.absoluteString
    } else {
      return
    }
    draftInstanceURL = newValue
    guard newValue != instanceURL else { return }
    instanceURL = newValue
    Task {
      await AnodyneClient.shared.clearCache()
      cacheSize = await AnodyneClient.shared.cacheSize()
    }
  }
}
