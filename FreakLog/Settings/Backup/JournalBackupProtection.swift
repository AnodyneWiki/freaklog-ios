import CommonCrypto
import CryptoKit
import Foundation

enum JournalBackupProtection {
  enum Failure: LocalizedError, Equatable {
    case damaged
    case tooLarge
    case invalidPassphrase
    case authentication
    case cannotProtect

    var errorDescription: String? {
      switch self {
      case .damaged: "This protected backup is incomplete or damaged."
      case .tooLarge: "This backup is too large to protect or open with a passphrase."
      case .invalidPassphrase: "Enter a passphrase of up to 1,024 UTF-8 bytes."
      case .authentication: "The passphrase is incorrect or the backup has been modified."
      case .cannotProtect: "FreakLog couldn’t protect this backup."
      }
    }
  }

  // Version 2 is the outer file format. The decrypted data is a complete native backup,
  // so the journal schema and its upgrades stay independent of the encryption parameters.
  private static let header = Data("FREAKLOG-BACKUP/2\n".utf8)
  private static let saltLength = 16
  private static let iterations: UInt32 = 600_000
  private static let maximumFileSize = 128 * 1024 * 1024
  private static let authenticationOverhead = 12 + 16
  static let maximumPassphraseBytes = 1024

  static func isProtected(_ data: Data) -> Bool {
    data.starts(with: header)
  }

  static func validateEnvelope(_ data: Data) throws {
    guard isProtected(data), data.count > header.count + saltLength + authenticationOverhead else {
      throw Failure.damaged
    }
    guard data.count <= maximumFileSize else { throw Failure.tooLarge }
  }

  static func protect(_ data: Data, passphrase: String) throws -> Data {
    guard data.count <= maximumFileSize - header.count - saltLength - authenticationOverhead else {
      throw Failure.tooLarge
    }
    let salt = SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
    let key = try deriveKey(passphrase: passphrase, salt: salt)
    let authenticatedHeader = header + salt
    guard let encrypted = try AES.GCM.seal(data, using: key, authenticating: authenticatedHeader).combined else {
      throw Failure.cannotProtect
    }
    return authenticatedHeader + encrypted
  }

  static func open(_ data: Data, passphrase: String) throws -> Data {
    try validateEnvelope(data)
    let authenticatedHeader = Data(data.prefix(header.count + saltLength))
    let salt = Data(authenticatedHeader.suffix(saltLength))
    let key = try deriveKey(passphrase: passphrase, salt: salt)
    let encrypted = try AES.GCM.SealedBox(combined: data.dropFirst(authenticatedHeader.count))
    do {
      return try AES.GCM.open(encrypted, using: key, authenticating: authenticatedHeader)
    } catch {
      throw Failure.authentication
    }
  }

  private static func deriveKey(passphrase: String, salt: Data) throws -> SymmetricKey {
    let normalized = passphrase.precomposedStringWithCanonicalMapping
    guard !normalized.isEmpty, normalized.utf8.count <= maximumPassphraseBytes else {
      throw Failure.invalidPassphrase
    }
    let password = Data(normalized.utf8)
    var derivedKey = Data(count: 32)
    let keyLength = derivedKey.count
    let status = derivedKey.withUnsafeMutableBytes { output in
      password.withUnsafeBytes { input in
        salt.withUnsafeBytes { saltBytes in
          CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            input.bindMemory(to: Int8.self).baseAddress, password.count,
            saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations,
            output.bindMemory(to: UInt8.self).baseAddress, keyLength)
        }
      }
    }
    guard status == kCCSuccess else { throw Failure.cannotProtect }
    return SymmetricKey(data: derivedKey)
  }
}
