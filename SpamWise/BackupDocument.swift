import SwiftUI
import UniformTypeIdentifiers
import SpamWiseCore

extension UTType {
  /// An encrypted SpamWise backup, declared by the app with the `.spamwisebackup` extension.
  static let spamWiseBackup = UTType(exportedAs: "codes.tim.spamwise.backup", conformingTo: .data)
}

/// Bytes saved through a file exporter: an encrypted backup, a recovery key or set-aside data.
struct BackupDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.spamWiseBackup, .plainText, .json] }
  var data: Data

  init(data: Data) { self.data = data }

  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else {
      throw BackupError.invalidArchive
    }
    self.data = data
  }

  func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}
