import Foundation
import PDFKit

enum PDFExtraction {
  static func extract(_ data: Data) -> DocumentResult {
    guard data.count <= DocumentWorkerLimits.inputBytes else { return .init(status: .inputLimit) }
    guard let document = PDFDocument(data: data) else { return .init(status: .malformed) }
    guard !document.isEncrypted, !document.isLocked else { return .init(status: .encrypted) }
    guard document.pageCount > 0, document.pageCount <= DocumentWorkerLimits.pages else {
      return .init(status: .pageLimit)
    }
    var text = ""
    for index in 0..<document.pageCount {
      guard let pageText = document.page(at: index)?.string else {
        return .init(status: .unreadable)
      }
      text += pageText.prefix(DocumentWorkerLimits.textCharacters - text.count)
      if text.count == DocumentWorkerLimits.textCharacters { break }
      text += "\n"
    }
    return .init(status: .extracted, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
  }
}
