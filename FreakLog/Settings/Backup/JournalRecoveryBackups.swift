import CryptoKit
import Foundation
import Security

enum JournalRecoveryBackups {
  struct Entry: Identifiable, Sendable {
    let url: URL
    let created: Date

    var id: URL { url }
  }

  enum Failure: LocalizedError {
    case cannotSave
    case cannotOpen

    var errorDescription: String? {
      switch self {
      case .cannotSave: "The recovery copy couldn’t be saved. Try again or turn off Save a Recovery Copy for this import."
      case .cannotOpen: "This recovery copy couldn’t be opened on this device."
      }
    }
  }

  private static let header = Data("FREAKLOG-RECOVERY/1\n".utf8)
  private static let retainedCount = 3

  static func saveVerified(_ plaintext: Data) throws {
    do {
      let key = try deviceKey(createIfMissing: true)
      guard let ciphertext = try AES.GCM.seal(plaintext, using: key, authenticating: header).combined else {
        throw Failure.cannotSave
      }
      let directory = try directory()
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      var excludedDirectory = directory
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try excludedDirectory.setResourceValues(values)
      let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("freaklogrecovery")
      try (header + ciphertext).write(to: url, options: [.atomic, .completeFileProtection])
      do {
        guard try open(url) == plaintext else { throw Failure.cannotSave }
      } catch {
        try? FileManager.default.removeItem(at: url)
        throw error
      }
      // A cleanup failure leaves an extra, usable copy and never invalidates the new one.
      for entry in (try? entries().dropFirst(retainedCount)) ?? [] {
        try? FileManager.default.removeItem(at: entry.url)
      }
    } catch {
      throw Failure.cannotSave
    }
  }

  static func entries() throws -> [Entry] {
    let directory = try directory()
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    return try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)
      .compactMap { url in
        guard url.pathExtension == "freaklogrecovery",
              let date = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        else { return nil }
        return Entry(url: url, created: date)
      }
      .sorted { $0.created > $1.created }
  }

  static func open(_ url: URL) throws -> Data {
    do {
      let data = try Data(contentsOf: url)
      guard data.starts(with: header) else { throw Failure.cannotOpen }
      let ciphertext = try AES.GCM.SealedBox(combined: data.dropFirst(header.count))
      return try AES.GCM.open(ciphertext, using: deviceKey(createIfMissing: false), authenticating: header)
    } catch {
      throw Failure.cannotOpen
    }
  }

  static func removeAll() throws {
    let directory = try directory()
    if FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
  }

  private static func directory() throws -> URL {
    try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      .appendingPathComponent("Journal Recovery", isDirectory: true)
  }

  private static let keyQuery: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "FreakLog Journal Recovery",
    kSecAttrAccount as String: "backup-key-v1",
  ]

  private static func deviceKey(createIfMissing: Bool) throws -> SymmetricKey {
    var lookup: [String: Any] = keyQuery
    lookup[kSecReturnData as String] = true
    lookup[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(lookup as CFDictionary, &result)
    if status == errSecSuccess, let data = result as? Data, data.count == 32 {
      return SymmetricKey(data: data)
    }
    guard createIfMissing, status == errSecItemNotFound else { throw Failure.cannotOpen }
    let key = SymmetricKey(size: .bits256)
    var item: [String: Any] = keyQuery
    item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    item[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
    switch SecItemAdd(item as CFDictionary, nil) {
    case errSecSuccess: return key
    case errSecDuplicateItem: return try deviceKey(createIfMissing: false)
    default: throw Failure.cannotSave
    }
  }
}

import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class JournalAutomaticBackups: ObservableObject {
  static let shared = JournalAutomaticBackups()

  struct Destination: Codable {
    let id: UUID
    let bookmark: Data
    let name: String
    var lastSuccess: Date?
  }

  private static let destinationKey = "journalAutomaticBackupDestination"
  private static let interval: TimeInterval = 24 * 60 * 60
  private nonisolated static let retainedCount = 3

  @Published private(set) var destination: Destination?
  @Published private(set) var isSaving = false
  @Published private(set) var failure: String?

  private init() {
    if let data = UserDefaults.standard.data(forKey: Self.destinationKey) {
      destination = try? JSONDecoder().decode(Destination.self, from: data)
    }
  }

  func configure(folder: URL, passphrase: String) throws {
    guard !isSaving, !passphrase.isEmpty,
          passphrase.precomposedStringWithCanonicalMapping.utf8.count <= JournalBackupProtection.maximumPassphraseBytes
    else { throw Failure.settings }
    guard folder.startAccessingSecurityScopedResource() else { throw Failure.destination }
    defer { folder.stopAccessingSecurityScopedResource() }
    let bookmark = try folder.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    let previous = destination
    let new = Destination(id: UUID(), bookmark: bookmark, name: folder.lastPathComponent)
    var item = Self.keyQuery(new.id)
    item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    item[kSecValueData as String] = Data(passphrase.utf8)
    guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw Failure.passphrase }
    do {
      try persist(new)
    } catch {
      SecItemDelete(Self.keyQuery(new.id) as CFDictionary)
      throw error
    }
    if let previous { SecItemDelete(Self.keyQuery(previous.id) as CFDictionary) }
    failure = nil
  }

  func disable() {
    guard !isSaving, let destination else { return }
    UserDefaults.standard.removeObject(forKey: Self.destinationKey)
    SecItemDelete(Self.keyQuery(destination.id) as CFDictionary)
    self.destination = nil
    failure = nil
  }

  func save(force: Bool = false) async {
    guard !isSaving, var destination,
          force || destination.lastSuccess.map({ Date.now.timeIntervalSince($0) >= Self.interval }) != false
    else { return }
    isSaving = true
    defer { isSaving = false }
    do {
      try Task.checkCancellation()
      let passphrase = try Self.passphrase(for: destination.id)
      let export = try await SettingsScreen.ViewModel().exportBackup()
      let plaintext = export.file.data
      try Task.checkCancellation()
      let protected = try await Task.detached(priority: .utility) {
        try JournalBackupProtection.protect(plaintext, passphrase: passphrase)
      }.value
      try Task.checkCancellation()
      let folder = destination
      try await Task.detached(priority: .utility) {
        try Self.writeAndVerify(protected, plaintext: plaintext, passphrase: passphrase, destination: folder)
      }.value
      destination.lastSuccess = .now
      try persist(destination)
      failure = nil
    } catch is CancellationError {
      return
    } catch {
      failure = "Backup couldn’t be completed. Choose the folder again if access changed, or try Back Up Now."
    }
  }

  private func persist(_ destination: Destination) throws {
    let data = try JSONEncoder().encode(destination)
    UserDefaults.standard.set(data, forKey: Self.destinationKey)
    self.destination = destination
  }

  private nonisolated static func keyQuery(_ id: UUID) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "FreakLog Automatic Backup",
      kSecAttrAccount as String: id.uuidString,
    ]
  }

  private static func passphrase(for id: UUID) throws -> String {
    var query = keyQuery(id)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
          let data = result as? Data,
          let passphrase = String(data: data, encoding: .utf8)
    else { throw Failure.passphrase }
    return passphrase
  }

  private nonisolated static func writeAndVerify(
    _ encrypted: Data, plaintext: Data, passphrase: String, destination: Destination
  ) throws {
    var stale = false
    let folder = try URL(resolvingBookmarkData: destination.bookmark, bookmarkDataIsStale: &stale)
    guard !stale, folder.startAccessingSecurityScopedResource() else { throw Failure.destination }
    defer { folder.stopAccessingSecurityScopedResource() }
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var outcome: Result<Void, Error> = .failure(Failure.destination)
    coordinator.coordinate(writingItemAt: folder, options: [], error: &coordinationError) { accessibleFolder in
      outcome = Result {
        let prefix = "FreakLog Automatic \(destination.id.uuidString) "
        let timestamp = Date.now.ISO8601Format().replacingOccurrences(of: ":", with: "-")
        let name = prefix + timestamp + " " + UUID().uuidString + ".freaklogbackup"
        let url = accessibleFolder.appendingPathComponent(name)
        do {
          try encrypted.write(to: url, options: .atomic)
          let saved = try Data(contentsOf: url)
          guard try JournalBackupProtection.open(saved, passphrase: passphrase) == plaintext else {
            throw Failure.verification
          }
        } catch {
          try? FileManager.default.removeItem(at: url)
          throw error
        }
        // Prune only this configuration's own files, after decrypting and verifying the new copy.
        let old = try? FileManager.default.contentsOfDirectory(at: accessibleFolder, includingPropertiesForKeys: nil)
        let copies = (old ?? []).filter {
          $0 != url && $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "freaklogbackup"
        }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for oldCopy in copies.dropFirst(retainedCount - 1) {
          try? FileManager.default.removeItem(at: oldCopy)
        }
      }
    }
    if let coordinationError { throw coordinationError }
    try outcome.get()
  }

  enum Failure: LocalizedError {
    case destination, settings, passphrase, verification

    var errorDescription: String? {
      switch self {
      case .destination: "The selected folder couldn’t be opened."
      case .settings: "The backup settings couldn’t be saved."
      case .passphrase: "The backup passphrase couldn’t be stored or read."
      case .verification: "The saved backup couldn’t be verified."
      }
    }
  }
}

struct JournalAutomaticBackupScreen: View {
  @ObservedObject private var backups = JournalAutomaticBackups.shared
  @State private var isChoosingFolder = false
  @State private var folder: URL?
  @State private var passphrase = ""
  @State private var confirmation = ""
  @State private var setupError: String?

  var body: some View {
    Form {
      if let destination = backups.destination {
        Section("Current Destination") {
          LabeledContent("Folder", value: destination.name)
          if let saved = destination.lastSuccess {
            LabeledContent("Last Verified Copy") {
              Text(saved.formatted(date: .abbreviated, time: .shortened))
            }
          }
          Button("Back Up Now") { Task { await backups.save(force: true) } }
          if backups.isSaving { ProgressView("Writing and Verifying Backup…") }
          if let failure = backups.failure { Text(failure).foregroundStyle(.secondary) }
        }
      }
      Section {
        Button {
          isChoosingFolder = true
        } label: {
          Label(folder?.lastPathComponent ?? "Choose Folder", systemImage: "folder")
        }
        if let folder {
          SecureField("Passphrase", text: $passphrase)
            .textContentType(.newPassword)
          SecureField("Confirm Passphrase", text: $confirmation)
            .textContentType(.newPassword)
          Button(backups.destination == nil ? "Enable Automatic Backups" : "Update Backup Destination") {
            configure(folder)
          }
          .disabled(passphrase.isEmpty || passphrase != confirmation
                    || passphrase.precomposedStringWithCanonicalMapping.utf8.count > JournalBackupProtection.maximumPassphraseBytes)
        }
        if let setupError { Text(setupError).foregroundStyle(.secondary) }
      } footer: {
        Text("FreakLog saves up to three encrypted copies. Automatic backups run when you open your unlocked journal and at least 24 hours have passed since the last verified copy. Keep the passphrase to restore a copy on another device.")
      }
      if backups.destination != nil {
        Section {
          Button("Turn Off Automatic Backups", role: .destructive) { backups.disable() }
        } footer: {
          Text("Copies already stored in the folder stay there.")
        }
      }
    }
    .disabled(backups.isSaving)
    .navigationTitle("Automatic Backups")
    .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
      switch result {
      case .success(let url):
        folder = url
        setupError = nil
      case .failure:
        setupError = "The selected folder couldn’t be opened."
      }
    }
  }

  private func configure(_ folder: URL) {
    do {
      try backups.configure(folder: folder, passphrase: passphrase)
      self.folder = nil
      passphrase = ""
      confirmation = ""
      setupError = nil
      Task { await backups.save(force: true) }
    } catch {
      setupError = error.localizedDescription
    }
  }
}
