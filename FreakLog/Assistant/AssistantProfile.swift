import Foundation
import Security

// MARK: - AssistantPreset

// Starting points for a provider. A preset fills in the API, the server address and, where it is stable, a
// model; Fetch Models in the editor lists what the server really offers.
enum AssistantPreset: String, Codable, CaseIterable, Identifiable {
  case onDevice
  case anthropic
  case openAI
  case gemini
  case openRouter
  case mistral
  case groq
  case deepSeek
  case ollama
  case lmStudio
  case customOpenAI
  case customAnthropic

  // The presets offered for a new provider; the on-device model only where it can exist
  static var available: [AssistantPreset] {
    allCases.filter { $0 != .onDevice || OnDeviceModel.isSupportedBySystem }
  }

  var id: Self { self }

  var name: String {
    switch self {
    case .onDevice: "Apple On-Device Model"
    case .anthropic: "Anthropic"
    case .openAI: "OpenAI"
    case .gemini: "Google Gemini"
    case .openRouter: "OpenRouter"
    case .mistral: "Mistral"
    case .groq: "Groq"
    case .deepSeek: "DeepSeek"
    case .ollama: "Ollama"
    case .lmStudio: "LM Studio"
    case .customOpenAI: "Other OpenAI-Compatible"
    case .customAnthropic: "Other Anthropic-Compatible"
    }
  }

  var standard: AssistantAPIStandard {
    switch self {
    case .onDevice: .onDevice
    case .anthropic, .customAnthropic: .anthropicMessages
    case .gemini: .gemini
    default: .openAIChat
    }
  }

  var baseURL: String {
    switch self {
    case .onDevice, .customOpenAI, .customAnthropic: ""
    case .anthropic: "https://api.anthropic.com/v1"
    case .openAI: "https://api.openai.com/v1"
    case .gemini: "https://generativelanguage.googleapis.com/v1beta"
    case .openRouter: "https://openrouter.ai/api/v1"
    case .mistral: "https://api.mistral.ai/v1"
    case .groq: "https://api.groq.com/openai/v1"
    case .deepSeek: "https://api.deepseek.com/v1"
    case .ollama: "http://localhost:11434/v1"
    case .lmStudio: "http://localhost:1234/v1"
    }
  }

  var suggestedModel: String {
    switch self {
    case .anthropic: "claude-opus-5-5"
    case .openRouter: "openrouter/auto"
    case .mistral: "mistral-large-latest"
    case .deepSeek: "deepseek-chat"
    default: ""
    }
  }

  var needsAPIKey: Bool {
    switch self {
    case .onDevice, .ollama, .lmStudio, .customOpenAI, .customAnthropic: false
    default: true
    }
  }

  var isCustom: Bool {
    self == .customOpenAI || self == .customAnthropic
  }

  var hint: String {
    switch self {
    case .onDevice: "Runs with Apple Intelligence on this device and works best for short chats. Enabled online lookups send queries to those services."
    case .anthropic: "Create an API key at console.anthropic.com."
    case .openAI: "Create an API key at platform.openai.com, then fetch the models."
    case .gemini: "Create an API key at aistudio.google.com, then fetch the models."
    case .openRouter: "One key for models of many providers, from openrouter.ai."
    case .mistral: "Create an API key at console.mistral.ai."
    case .groq: "Create an API key at console.groq.com, then fetch the models."
    case .deepSeek: "Create an API key at platform.deepseek.com."
    case .ollama: "localhost only reaches a server on this device, such as on a Mac. For another computer, put an HTTPS reverse proxy in front of Ollama."
    case .lmStudio: "localhost only reaches a server on this device, such as on a Mac. For another computer, put an HTTPS reverse proxy in front of LM Studio."
    case .customOpenAI: "Any server with /chat/completions, e.g. vLLM, llama.cpp or LiteLLM. Include /v1 if it uses it."
    case .customAnthropic: "Any server with the Anthropic /messages API. Include /v1 if it uses it."
    }
  }

}

// MARK: - AssistantProfile

// A saved provider. Its API key is kept apart in the keychain.
struct AssistantProfile: Codable, Hashable, Identifiable {
  init(preset: AssistantPreset) {
    name = preset.name
    self.preset = preset
    standard = preset.standard
    baseURL = preset.baseURL
    model = preset.suggestedModel
    maxOutputTokens = preset.standard == .anthropicMessages ? AnthropicMessagesClient.defaultMaxOutputTokens : nil
  }

  var id = UUID()
  var name: String
  var preset: AssistantPreset
  var standard: AssistantAPIStandard
  var baseURL: String
  var model: String
  // Nil leaves the limit to the provider, except for the Anthropic API, which needs one
  var maxOutputTokens: Int?
  // Models chosen before, newest first, offered first in the chat's model menu
  var recentModels: [String]?

  static let maxRecentModels = 5

  // The model, and the models chosen before it, for the chat's model menu
  var quickModels: [String] {
    ([model] + (recentModels ?? [])).filter { !$0.isEmpty }.uniqued()
  }

  // Makes the model the profile's, remembering the one before
  mutating func choose(model newModel: String) {
    guard newModel != model else { return }
    recentModels = Array(([model] + (recentModels ?? [])).filter { !$0.isEmpty && $0 != newModel }.uniqued()
      .prefix(Self.maxRecentModels))
    model = newModel
  }

  // What the chat's title shows
  var modelName: String {
    standard == .onDevice ? "On-Device Model" : model
  }

  // What the provider's row and the chat show, e.g. "claude-opus-5-5 · Anthropic Messages"
  var caption: String {
    if standard == .onDevice {
      return standard.name
    }
    return "\(model.isEmpty ? "No model chosen" : model) · \(standard.name)"
  }

  // The client that speaks the profile's API
  func client(apiKey: String) -> (any AssistantChatClient)? {
    let endpoint = AssistantEndpoint(baseURL: baseURL, apiKey: apiKey)
    return switch standard {
    case .openAIChat: OpenAIChatClient(endpoint: endpoint)
    case .anthropicMessages: AnthropicMessagesClient(endpoint: endpoint)
    case .gemini: GeminiClient(endpoint: endpoint)
    case .onDevice: nil
    }
  }
}

// MARK: - AssistantProfileStore

// The saved providers and the one chats use. The list lives in user defaults and is included in journal backups.
enum AssistantProfileStore {
  static var profiles: [AssistantProfile] {
    profiles(from: UserDefaults.standard.data(forKey: PersistenceController.assistantProfilesKey))
  }

  // The chosen profile, else the first one
  static var activeProfile: AssistantProfile? {
    let profiles = profiles
    let id = UserDefaults.standard.string(forKey: PersistenceController.assistantActiveProfileKey)
    return profiles.first { $0.id.uuidString == id } ?? profiles.first
  }

  // Whether the assistant may look substances up on AnodyneWiki, on unless turned off
  static var isAnodyneWikiEnabled: Bool {
    UserDefaults.standard.object(forKey: PersistenceController.isAssistantAnodyneWikiEnabledKey) as? Bool ?? true
  }

  static func profiles(from data: Data?) -> [AssistantProfile] {
    guard let data, let profiles = try? JSONDecoder().decode([AssistantProfile].self, from: data) else { return [] }
    return profiles
  }

  static func setActive(_ id: UUID) {
    UserDefaults.standard.set(id.uuidString, forKey: PersistenceController.assistantActiveProfileKey)
  }

  static func restore(
    profilesFrom data: Data?,
    activeID: String?,
    to defaults: UserDefaults,
    mayHaveKey: (UUID) -> Bool = AssistantKeychain.mayHaveKey)
  {
    let profilesKey = PersistenceController.assistantProfilesKey
    let localProfiles = profiles(from: defaults.data(forKey: profilesKey))
    var restoredActiveID: String?
    let restoredProfiles = profiles(from: data).map { saved -> AssistantProfile in
      var profile = saved
      let local = localProfiles.first { $0.id == saved.id }
      // Reuse a local key only when the profile still points to its original server.
      if !AssistantHTTP.sameOrigin(local.flatMap { URL(string: $0.baseURL) }, URL(string: saved.baseURL)),
         mayHaveKey(saved.id)
      {
        profile.id = UUID()
      }
      if saved.id.uuidString == activeID {
        restoredActiveID = profile.id.uuidString
      }
      return profile
    }
    defaults.set(restoredProfiles.isEmpty ? nil : try? JSONEncoder().encode(restoredProfiles), forKey: profilesKey)
    defaults.set(restoredActiveID, forKey: PersistenceController.assistantActiveProfileKey)
  }

  static func save(_ profile: AssistantProfile) {
    var profiles = profiles
    if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
      profiles[index] = profile
    } else {
      profiles.append(profile)
    }
    write(profiles)
    if activeProfile == nil || profiles.count == 1 {
      setActive(profile.id)
    }
  }

  static func delete(_ id: UUID) throws {
    try AssistantKeychain.setKey("", for: id)
    let remaining = profiles.filter { $0.id != id }
    write(remaining)
    if UserDefaults.standard.string(forKey: PersistenceController.assistantActiveProfileKey) == id.uuidString {
      if let first = remaining.first {
        setActive(first.id)
      } else {
        UserDefaults.standard.removeObject(forKey: PersistenceController.assistantActiveProfileKey)
      }
    }
  }

  private static func write(_ profiles: [AssistantProfile]) {
    UserDefaults.standard.set(try? JSONEncoder().encode(profiles), forKey: PersistenceController.assistantProfilesKey)
  }

}

// MARK: - AssistantKeychain

// API keys, kept in the keychain of this device only: never synced through iCloud Keychain, never in backups of
// the device, and only readable while it is unlocked
enum AssistantKeychain {
  static func key(for id: UUID) -> String {
    var query = query(for: id)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
    return String(decoding: data, as: UTF8.self)
  }

  static func hasKey(for id: UUID) -> Bool {
    !key(for: id).isEmpty
  }

  // An inaccessible item can still become readable after the device is unlocked.
  static func mayHaveKey(for id: UUID) -> Bool {
    SecItemCopyMatching(query(for: id) as CFDictionary, nil) != errSecItemNotFound
  }

  // An empty key removes the saved one
  static func setKey(_ key: String, for id: UUID) throws {
    let query = query(for: id)
    let status: OSStatus
    if key.isEmpty {
      status = SecItemDelete(query as CFDictionary)
      if status == errSecItemNotFound { return }
    } else {
      let attributes = [kSecValueData as String: Data(key.utf8)]
      let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
      if updated == errSecItemNotFound {
        var item = query.merging(attributes) { _, value in value }
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        status = SecItemAdd(item as CFDictionary, nil)
      } else {
        status = updated
      }
    }
    guard status == errSecSuccess else {
      throw AssistantError("The keychain could not update this provider’s API key (\(status)).")
    }
  }

  private static let service = "FreakLog Assistant API Key"

  private static func query(for id: UUID) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: id.uuidString,
    ]
  }

}
