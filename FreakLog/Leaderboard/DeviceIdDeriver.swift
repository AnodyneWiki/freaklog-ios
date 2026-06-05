import CryptoKit
import Foundation

enum DeviceIdDeriver {
  static func deviceId(for host: String) -> String {
    let seed = loadOrCreateSeed()
    let key = SymmetricKey(data: Data(seed.utf8))
    let normalized = normalizeHost(host)
    let mac = HMAC<SHA512>.authenticationCode(for: Data(normalized.utf8), using: key)
    return mac.map { String(format: "%02x", $0) }.joined()
  }

  static func maskedDeviceId(for host: String) -> String {
    let full = deviceId(for: host)
    guard full.count >= 16 else { return full }
    let prefix = String(full.prefix(8))
    let suffix = String(full.suffix(8))
    return "\(prefix)\u{2026}\(suffix)"
  }

  private static func normalizeHost(_ host: String) -> String {
    var result = host.trimmingCharacters(in: .whitespaces).lowercased()
    while result.hasSuffix(".") {
      result = String(result.dropLast())
    }
    return result
  }

  private static func loadOrCreateSeed() -> String {
    let key = PersistenceController.leaderboardDeviceSeedKey
    if let existing = UserDefaults.standard.string(forKey: key) {
      return existing
    }
    let new = UUID().uuidString
    UserDefaults.standard.set(new, forKey: key)
    return new
  }
}
