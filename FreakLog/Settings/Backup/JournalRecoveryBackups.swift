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
