import Foundation

/// Input-file failures that every bounded evaluation reader reports in its own error type.
protocol BoundedInputError: Error {
  /// The path names a directory or other non-regular file, after resolving links.
  static func notRegularFile(_ url: URL) -> Self
  /// The file is larger than the reader accepts.
  static func fileTooLarge(_ url: URL, limit: Int) -> Self
}

extension BoundedInputError {
  /// Reads a regular file of at most `limit` bytes, following symbolic links.
  static func boundedContents(of url: URL, limit: Int) throws -> Data {
    let resolved = url.resolvingSymlinksInPath()
    let properties = try resolved.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard properties.isRegularFile == true else { throw notRegularFile(url) }
    guard (properties.fileSize ?? Int.max) <= limit else { throw fileTooLarge(url, limit: limit) }
    let data = try Data(contentsOf: resolved)
    guard data.count <= limit else { throw fileTooLarge(url, limit: limit) }
    return data
  }
}
