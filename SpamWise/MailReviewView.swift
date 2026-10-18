import SwiftUI
import SpamWiseCore
import MailIntegration

struct MailReviewView: View {
  let review: JunkReviewModel
  @State private var accountID = ""
  @State private var offset = 0
  @State private var selection: String?
  @Environment(\.dismiss) private var dismiss

  private var selected: ReviewMessage? { review.messages.first { $0.id == selection } }

  private var selectedText: String {
    guard let selected else { return String(localized: "Select a message") }
    return selected.text ?? String(localized: "Couldn’t read the message.")
  }

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading) {
        Text(
          "Folder membership is not a confirmed label. Reading this list does not classify or move mail."
        )
        .foregroundStyle(.secondary)
        HStack {
          Picker("Account", selection: $accountID) {
            Text("Choose account").tag("")
            ForEach(review.accounts) { Text($0.name).tag($0.id) }
          }
          Button("Load page") { review.load(accountID: accountID, offset: offset) }
            .disabled(accountID.isEmpty)
        }
        HSplitView {
          List(review.messages, selection: $selection) { message in
            Text(message.displaySubject).tag(message.id)
          }.frame(minWidth: 220)
          ScrollView {
            Text(selectedText)
              .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding()
          }.frame(minWidth: 300)
        }
        HStack {
          Button("Previous page") { showPage(at: max(0, offset - JunkReviewModel.pageSize)) }
            .disabled(offset == 0)
          Button("Next page") { showPage(at: offset + JunkReviewModel.pageSize) }
            .disabled(offset + JunkReviewModel.pageSize >= review.total)
          Spacer()
          if review.operation.isBusy { ProgressView().controlSize(.small) }
          Button("Mark Good and restore") {
            if let selected { review.restore(selected.envelope) }
          }
          .disabled(selected == nil)
        }
        OperationStatusView(operation: review.operation)
      }
      .padding()
      .navigationTitle("Review Junk")
      .toolbar { DoneToolbarItem(dismiss: dismiss, identifier: "junk.done") }
    }
    .frame(minWidth: 720, minHeight: 480)
    .task { review.discoverAccounts() }
    .onChange(of: accountID) { _, _ in
      offset = 0; selection = nil; review.clear()
    }
  }

  private func showPage(at offset: Int) {
    self.offset = offset
    review.load(accountID: accountID, offset: offset)
  }
}

struct CorrectionResultsView: View {
  let corrections: CorrectionsModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading) {
        List(corrections.selectionResults) { result in
          VStack(alignment: .leading) {
            Text(result.subject)
            if let record = result.record {
              Text("Correction saved. Mail action: \(record.outcome.localizedTitle).")
              if let error = record.actionError { Text(error) }
            } else {
              Text(result.error ?? String(localized: "Correction unavailable"))
            }
          }
        }
        .overlay {
          if corrections.selection.isBusy, corrections.selectionResults.isEmpty {
            ProgressView()
          }
        }
        OperationStatusView(operation: corrections.selection).padding(.horizontal)
      }
      .navigationTitle("Selected-message corrections")
      .toolbar { DoneToolbarItem(dismiss: dismiss, identifier: "corrections.done") }
    }
    .frame(minWidth: 520, minHeight: 320)
  }
}

/// A message's text in its own sheet.
struct MessagePreviewSheet: View {
  let preview: MessagePreview
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      MessageTextView(text: preview.text)
        .navigationTitle("Message preview")
        .toolbar { DoneToolbarItem(dismiss: dismiss, identifier: "preview.done") }
    }
    .frame(minWidth: 560, minHeight: 400)
  }
}

/// A message's plain text, selectable and scrollable.
struct MessageTextView: View {
  let text: String

  var body: some View {
    ScrollView {
      Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
  }
}

#Preview("Junk review") { MailReviewView(review: PreviewHelper.model().junkReview) }
#Preview("Corrections") { CorrectionResultsView(corrections: PreviewHelper.model().corrections) }
#Preview("Plain-text preview") {
  MessagePreviewSheet(preview: MessagePreview(text: "A safe local message preview."))
}
