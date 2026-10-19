import Foundation
import SwiftUI
import UniformTypeIdentifiers
import SpamWiseCore

struct RulesDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.json, .data] }
  var data: Data

  init(data: Data) { self.data = data }
  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else {
      throw RuleManagementError.invalidArchive
    }
    self.data = data
  }
  func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}

extension JSONEncoder {
  static var pretty: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }
}
