import SwiftUI
import UniformTypeIdentifiers

extension UTType {
  static let freakLogBackup = UTType(exportedAs: "woof.freaklog.backup", conformingTo: .data)
  static let androidEncryptedJournal = UTType(filenameExtension: "enc", conformingTo: .data) ?? .data
}

// A file to export: a backup or a journal file, already encoded
struct ExportedFile: FileDocument {
  static let readableContentTypes: [UTType] = [.json, .freakLogBackup, .androidEncryptedJournal]

  let data: Data
  let filename: String
  let contentType: UTType

  init(data: Data = Data(), filename: String = "", contentType: UTType = .json) {
    self.data = data
    self.filename = filename
    self.contentType = contentType
  }

  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
    self.data = data
    filename = configuration.file.filename ?? ""
    contentType = configuration.contentType
  }

  func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}
