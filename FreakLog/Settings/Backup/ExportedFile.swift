import SwiftUI
import UniformTypeIdentifiers

// A file to export: a backup or a journal file, already encoded
struct ExportedFile: FileDocument {
  static let readableContentTypes = [UTType.json]

  let data: Data
  let filename: String

  init(data: Data = Data(), filename: String = "") {
    self.data = data
    self.filename = filename
  }

  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
    self.data = data
    filename = configuration.file.filename ?? ""
  }

  func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}
