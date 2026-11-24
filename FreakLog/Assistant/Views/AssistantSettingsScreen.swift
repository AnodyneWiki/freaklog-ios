import SwiftUI

// MARK: - AssistantSettingsScreen

struct AssistantSettingsScreen: View {
  var body: some View {
    Form {
      Section {
        Toggle("Assistant", isOn: $isEnabled)
      } footer: {
        Text(
          "Chat about your journal from the journal and from each experience, and have sessions summarized. Your messages, and the journal entries and substance data the assistant looks up, go to the provider you choose. Apple's on-device model keeps them on this device.")
      }
      Section {
        ForEach(profiles) { profile in
          NavigationLink(value: GlobalNavigationDestination.assistantProvider(id: profile.id)) {
            VStack(alignment: .leading, spacing: 2) {
              Text(profile.name)
              Text(profile.caption)
                .font(.footnote)
                .foregroundColor(.secondary)
              if let problem = AssistantChat.setupProblem(of: profile) {
                Text(problem)
                  .font(.footnote)
                  .foregroundColor(.orange)
              }
            }
          }
        }
        NavigationLink(value: GlobalNavigationDestination.assistantProvider(id: nil)) {
          Label("Add Provider", systemImage: "plus")
        }
      } header: {
        Text("Providers")
      } footer: {
        Text("Journal backups include providers and model settings. API keys stay in this device’s keychain.")
      }
      if profiles.count > 1 {
        Section {
          Picker("Use for Chats", selection: activeProfile) {
            ForEach(profiles) { profile in
              Text(profile.name).tag(Optional(profile.id))
            }
          }
        } footer: {
          Text("You can also switch providers in a chat.")
        }
      }
      Section {
        Toggle("Look Up Substances on AnodyneWiki", isOn: $isAnodyneWikiEnabled)
        if isAnodyneWikiEnabled {
          NavigationLink(value: GlobalNavigationDestination.anodyneSettings) {
            Text("AnodyneWiki Instance")
          }
        }
      } header: {
        Text("Substance Lookups")
      } footer: {
        Text(
          "Lets the assistant read dose tiers, interactions and warnings on AnodyneWiki when the app's data isn't enough. Only the titles of AnodyneWiki's own pages are requested, never the names of your custom substances.")
      }
    }
    .navigationTitle("Assistant")
  }

  @AppStorage(PersistenceController.isAssistantEnabledKey) private var isEnabled = false
  @AppStorage(PersistenceController.isAssistantAnodyneWikiEnabledKey) private var isAnodyneWikiEnabled = true
  @AppStorage(PersistenceController.assistantProfilesKey) private var profilesData = Data()
  @AppStorage(PersistenceController.assistantActiveProfileKey) private var activeProfileID = ""

  private var profiles: [AssistantProfile] {
    AssistantProfileStore.profiles(from: profilesData)
  }

  private var activeProfile: Binding<UUID?> {
    Binding {
      let profiles = profiles
      return (profiles.first { $0.id.uuidString == activeProfileID } ?? profiles.first)?.id
    } set: { id in
      activeProfileID = id?.uuidString ?? ""
    }
  }

}

// MARK: - AssistantProviderScreen

// Adds or edits a provider. Nothing is saved before Save.
struct AssistantProviderScreen: View {
  init(profileID: UUID?) {
    let existing = profileID.flatMap { id in AssistantProfileStore.profiles.first { $0.id == id } }
    let preset: AssistantPreset = OnDeviceModel.unavailableReason == nil ? .onDevice : .anthropic
    let profile = existing ?? AssistantProfile(preset: preset)
    _profile = State(initialValue: profile)
    originalURL = existing.flatMap { URL(string: $0.baseURL) }
    isNew = existing == nil
    _hasSavedKey = State(initialValue: existing.map { AssistantKeychain.hasKey(for: $0.id) } ?? false)
    _maxOutputTokensText = State(initialValue: profile.maxOutputTokens.map(String.init) ?? "")
  }

  var body: some View {
    Form {
      Section {
        Picker("Provider", selection: $profile.preset) {
          ForEach(AssistantPreset.available) { preset in
            Text(preset.name).tag(preset)
          }
        }
        TextField("Name", text: $profile.name)
      } footer: {
        Text(profile.preset.hint)
      }
      if isOnDevice {
        Section {
          LabeledContent("Status", value: OnDeviceModel.unavailableReason ?? "Ready")
        }
      } else {
        serverSections
      }
      if let problem {
        Section {
          Label(problem, systemImage: "exclamationmark.triangle")
            .foregroundColor(.orange)
        }
      }
      if !isNew {
        Section {
          Button("Delete Provider", role: .destructive) {
            isConfirmingDelete = true
          }
        }
      }
    }
    .navigationTitle(isNew ? "Add Provider" : profile.name)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Save", action: save)
          .disabled(problem != nil)
      }
    }
    .alert("Provider Settings", isPresented: Binding(get: { storageError != nil }, set: { if !$0 { storageError = nil } })) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(storageError ?? "")
    }
    .onChange(of: profile.baseURL) { [oldURL = profile.baseURL] url in
      if !AssistantHTTP.sameOrigin(URL(string: oldURL), URL(string: url)) {
        apiKey = ""
        profile.recentModels = nil
      }
      models = []
      modelsError = nil
      testResult = nil
    }
    .onChange(of: profile) { _ in clearConnectionTest() }
    .onChange(of: apiKey) { _ in clearConnectionTest() }
    .onChange(of: isRemovingSavedKey) { _ in clearConnectionTest() }
    .onChange(of: maxOutputTokensText) { _ in clearConnectionTest() }
    .onDisappear { clearConnectionTest() }
    .onChange(of: profile.preset) { [oldPreset = profile.preset] preset in
      apply(preset, replacing: oldPreset)
    }
    .confirmationDialog("Delete \(profile.name)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
      Button("Delete", role: .destructive) {
        do {
          try AssistantProfileStore.delete(profile.id)
          dismiss()
        } catch {
          storageError = error.localizedDescription
        }
      }
      Button("Cancel", role: .cancel) { }
    } message: {
      Text("The provider and its API key are removed from this device.")
    }
  }

  private enum TestResult {
    case testing
    case succeeded(String)
    case failed(String)
  }

  @Environment(\.dismiss) private var dismiss
  @State private var profile: AssistantProfile
  // A newly typed key; empty keeps the saved one
  @State private var apiKey = ""
  @State private var hasSavedKey: Bool
  @State private var isRemovingSavedKey = false
  @State private var maxOutputTokensText: String
  @State private var models: [String] = []
  @State private var isFetchingModels = false
  @State private var modelsError: String?
  @State private var connectionTest: Task<Void, Never>?
  @State private var testResult: TestResult?
  @State private var isConfirmingDelete = false

  @State private var storageError: String?
  private let originalURL: URL?
  private let isNew: Bool

  private var canUseSavedKey: Bool {
    hasSavedKey && !isRemovingSavedKey && AssistantHTTP.sameOrigin(originalURL, URL(string: profile.baseURL))
  }

  private var isOnDevice: Bool {
    profile.standard == .onDevice
  }

  // The key requests use: the typed one, else the saved one
  private var effectiveAPIKey: String {
    let typed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    if !typed.isEmpty {
      return typed
    }
    return canUseSavedKey ? AssistantKeychain.key(for: profile.id) : ""
  }

  private var maxOutputTokens: Int? {
    Int(maxOutputTokensText.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil }
  }

  private var problem: String? {
    if profile.name.trimmingCharacters(in: .whitespaces).isEmpty {
      return "Enter a name."
    }
    guard !isOnDevice else { return nil }
    if profile.baseURL.trimmingCharacters(in: .whitespaces).isEmpty {
      return "Enter the server address."
    }
    do {
      _ = try AssistantHTTP.url(profile.baseURL, "models")
    } catch {
      return error.localizedDescription
    }
    if profile.model.trimmingCharacters(in: .whitespaces).isEmpty {
      return "Choose a model."
    }
    if profile.standard == .anthropicMessages, maxOutputTokens == nil {
      return "The Anthropic API needs a limit for the output tokens."
    }
    return nil
  }

  @ViewBuilder
  private var serverSections: some View {
    Section {
      if profile.preset.isCustom {
        Picker("API", selection: $profile.standard) {
          ForEach(AssistantAPIStandard.serverStandards) { standard in
            Text(standard.name).tag(standard)
          }
        }
      }
      TextField("https://example.com/v1", text: $profile.baseURL)
        .keyboardType(.URL)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    } header: {
      Text("Server Address")
    } footer: {
      Text("The address the API's paths are added to, usually ending in /v1.")
    }
    Section {
      SecureField(canUseSavedKey ? "Saved, leave empty to keep it" : "API Key", text: $apiKey)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      if canUseSavedKey {
        Button("Remove Saved Key", role: .destructive) {
          isRemovingSavedKey = true
          apiKey = ""
        }
      }
    } header: {
      Text(profile.preset.needsAPIKey ? "API Key" : "API Key (Optional)")
    } footer: {
      Text("Kept in the keychain of this device and only sent to this provider.")
    }
    Section {
      TextField("Model ID", text: $profile.model)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      if !models.isEmpty {
        Picker("Fetched Models", selection: $profile.model) {
          if !models.contains(profile.model) {
            Text(profile.model.isEmpty ? "None" : profile.model).tag(profile.model)
          }
          ForEach(models, id: \.self) { model in
            Text(model).tag(model)
          }
        }
      }
      Button {
        fetchModels()
      } label: {
        HStack {
          Text("Fetch Models")
          if isFetchingModels {
            Spacer()
            ProgressView()
          }
        }
      }
      .disabled(isFetchingModels)
      if let modelsError {
        Text(modelsError)
          .font(.footnote)
          .foregroundColor(.red)
      }
    } header: {
      Text("Model")
    }
    Section {
      TextField(profile.standard == .anthropicMessages ? "Required" : "Provider's default", text: $maxOutputTokensText)
        .keyboardType(.numberPad)
    } header: {
      Text("Max Output Tokens")
    } footer: {
      Text("The upper limit for one answer, thinking included.")
    }
    Section {
      Button {
        test()
      } label: {
        HStack {
          Text("Test Connection")
          if case .testing = testResult {
            Spacer()
            ProgressView()
          }
        }
      }
      .disabled(problem != nil || { if case .testing = testResult { true } else { false } }())
      switch testResult {
      case .succeeded(let answer):
        Label("Connected. The model answered “\(answer.prefix(80))”.", systemImage: "checkmark.circle")
          .foregroundColor(.green)
      case .failed(let message):
        Label(message, systemImage: "xmark.circle")
          .foregroundColor(.red)
      default:
        EmptyView()
      }
    } footer: {
      Text("Sends a short test message to the model.")
    }
  }

  // A preset brings its API, address and model; a name that was the old preset's follows it too
  private func apply(_ preset: AssistantPreset, replacing oldPreset: AssistantPreset) {
    if profile.name == oldPreset.name || profile.name.isEmpty {
      profile.name = preset.name
    }
    profile.standard = preset.standard
    profile.baseURL = preset.baseURL
    profile.model = preset.suggestedModel
    profile.recentModels = nil
    if preset.standard == .anthropicMessages, maxOutputTokens == nil {
      maxOutputTokensText = String(AnthropicMessagesClient.defaultMaxOutputTokens)
    }
    models = []
    modelsError = nil
    testResult = nil
  }

  private func fetchModels() {
    guard let client = profile.client(apiKey: effectiveAPIKey) else { return }
    let address = profile.baseURL
    let standard = profile.standard
    isFetchingModels = true
    modelsError = nil
    Task {
      defer { isFetchingModels = false }
      do {
        let fetched = try await client.models()
        guard address == profile.baseURL, standard == profile.standard else { return }
        models = fetched.uniqued()
        if models.isEmpty {
          modelsError = "The server lists no models."
        } else if profile.model.isEmpty, let first = models.first {
          profile.model = first
        }
      } catch {
        guard address == profile.baseURL, standard == profile.standard else { return }
        modelsError = error.localizedDescription
      }
    }
  }

  private func clearConnectionTest() {
    connectionTest?.cancel()
    connectionTest = nil
    testResult = nil
  }

  private func test() {
    guard let client = profile.client(apiKey: effectiveAPIKey) else { return }
    testResult = .testing
    let request = AssistantRequest(
      model: profile.model,
      system: "You are checking that a connection works.",
      messages: [.user("Reply with the single word OK.")],
      tools: [],
      maxOutputTokens: maxOutputTokens)
    connectionTest = Task {
      do {
        let answer = try await client.complete(request).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !Task.isCancelled else { return }
        testResult = answer.isEmpty ? .failed("The model returned an empty answer.") : .succeeded(answer)
      } catch {
        guard !Task.isCancelled else { return }
        testResult = .failed(error.localizedDescription)
      }
    }
  }

  private func save() {
    profile.name = profile.name.trimmingCharacters(in: .whitespaces)
    profile.baseURL = profile.baseURL.trimmingCharacters(in: .whitespaces)
    profile.model = profile.model.trimmingCharacters(in: .whitespaces)
    profile.maxOutputTokens = isOnDevice ? nil : maxOutputTokens
    let typedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let key: String? = if isOnDevice || hasSavedKey && !canUseSavedKey && typedKey.isEmpty {
      isNew ? nil : ""
    } else {
      typedKey.isEmpty ? nil : typedKey
    }
    do {
      if let key { try AssistantKeychain.setKey(key, for: profile.id) }
      AssistantProfileStore.save(profile)
      dismiss()
    } catch {
      storageError = error.localizedDescription
    }
  }
}
