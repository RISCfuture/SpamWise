import Foundation

/// A user-chosen file couldn’t be read.
protocol FileImportFailure: Error {}

/// Why a user-chosen file was refused before it was read.
nonisolated enum FileImportError: FileImportFailure, LocalizedError, Equatable {
  /// The file is larger than SpamWise reads for this purpose.
  case tooLarge(name: String, maximumBytes: Int)

  var errorDescription: String? { String(localized: "Couldn’t read the file.") }
  var failureReason: String? {
    switch self {
      case let .tooLarge(name, maximumBytes):
        String(
          localized:
            "“\(name)” is larger than \(Measurement(value: Double(maximumBytes), unit: UnitInformationStorage.bytes), format: .byteCount(style: .file))."
        )
    }
  }
  var recoverySuggestion: String? { String(localized: "Choose a smaller file.") }
}

extension URL {
  /**
   Reads this user-chosen file through its security scope.

   Reads one byte past `maximumBytes`, so a larger file is refused rather than truncated.

   - Throws: ``FileImportError/tooLarge(name:maximumBytes:)`` for a larger file, or the error
     that prevented reading it.
   */
  nonisolated func readSecurityScoped(maximumBytes: Int) throws -> Data {
    let scoped = startAccessingSecurityScopedResource()
    defer { if scoped { stopAccessingSecurityScopedResource() } }
    let file = try FileHandle(forReadingFrom: self)
    defer { try? file.close() }
    let data = try file.read(upToCount: maximumBytes + 1) ?? Data()
    guard data.count <= maximumBytes else {
      throw FileImportError.tooLarge(name: lastPathComponent, maximumBytes: maximumBytes)
    }
    return data
  }
}
