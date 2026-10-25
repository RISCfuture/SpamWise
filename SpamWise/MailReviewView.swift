import SwiftUI
import SpamWiseCore
import MailIntegration

/// Reviews one account’s Junk mailbox and restores the messages that aren’t junk.
struct MailReviewView: View {
  let review: JunkReviewModel
  @State private var selection: JunkReviewRow.ID?
  @Environment(\.dismiss)
  private var dismiss

  private var selected: JunkReviewRow? { review.rows.first { $0.id == selection } }
  private var account: Binding<String?> {
    Binding(get: { review.accountID }, set: { review.choose(accountID: $0) })
  }

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading) {
        HStack {
          Text("Restore anything that isn’t junk. Nothing moves unless you choose Mark as Good.")
            .foregroundStyle(.secondary)
          Spacer()
          HelpButton(page: "review-junk")
        }
        Picker("Account", selection: account) {
          Text("Choose an account").tag(String?.none)
          ForEach(review.accounts) { Text($0.name).tag(Optional($0.id)) }
        }
        .fixedSize()
        .accessibilityIdentifier("junk.account")
        HSplitView {
          JunkMessageList(review: review, selection: $selection).frame(minWidth: 240)
          JunkMessageDetail(review: review, row: selected).frame(minWidth: 320)
        }
        JunkPager(review: review)
        OperationStatusView(operation: review.loading)
      }
      .padding()
      .navigationTitle("Review Junk")
      .toolbar { DoneToolbarItem(dismiss: dismiss, identifier: "junk.done") }
    }
    .frame(minWidth: 720, minHeight: 480)
    .task { review.discoverAccounts() }
    .onDisappear { review.choose(accountID: nil) }
    .onChange(of: review.accountID) { selection = nil }
  }
}

private struct JunkMessageList: View {
  let review: JunkReviewModel
  @Binding var selection: JunkReviewRow.ID?

  var body: some View {
    List(review.rows, selection: $selection) { row in
      VStack(alignment: .leading) {
        Text(row.message.displaySubject)
        if let sender = row.message.sender { Text(sender).foregroundStyle(.secondary) }
      }
    }
    .overlay { JunkListPlaceholder(review: review) }
  }
}

private struct JunkListPlaceholder: View {
  let review: JunkReviewModel

  var body: some View {
    if review.accountID == nil {
      ContentUnavailableView(
        "Choose an Account",
        systemImage: "tray",
        description: Text("Pick an account to see the messages in its Junk mailbox.")
      )
    } else if !review.hasLoaded, review.loading.isBusy {
      ProgressView()
    } else if review.hasLoaded, review.rows.isEmpty {
      ContentUnavailableView(
        "Nothing in Junk",
        systemImage: "tray",
        description: Text("This page has no messages to review.")
      )
    }
  }
}

private struct JunkMessageDetail: View {
  let review: JunkReviewModel
  let row: JunkReviewRow?
  @State private var confirmingRestore = false

  var body: some View {
    if let row {
      VStack(alignment: .leading) {
        Text(row.message.displaySubject).font(.headline).textSelection(.enabled)
        if let sender = row.message.sender {
          Text(sender).foregroundStyle(.secondary).textSelection(.enabled)
        }
        Text(row.provenance.localizedDescription)
        if let rule = review.blockingRule(for: row) {
          Text("Your Block rule for \(rule.value) matches this sender.")
        }
        MessageTextView(
          text: row.message.text ?? String(localized: "SpamWise couldn’t read this message.")
        )
        HStack {
          OperationStatusView(operation: review.restoring)
          Spacer()
          if review.restoring.isBusy { ProgressView().controlSize(.small) }
          Button("Mark as Good and Restore") { restore(row) }
            .disabled(review.restoring.isBusy)
            .accessibilityIdentifier("junk.restore")
        }
      }
      .padding()
      .confirmationDialog(
        "Allow mail from \(row.message.sender ?? "")?",
        isPresented: $confirmingRestore,
        presenting: review.blockingRule(for: row)
      ) { rule in
        Button(rule.scope == .address ? "Replace Rule and Restore" : "Allow Sender and Restore") {
          review.restore(row)
        }
      } message: { rule in
        Text(rule.restoreConsequence(sender: row.message.sender ?? ""))
      }
    } else {
      ContentUnavailableView("No Message Selected", systemImage: "envelope")
    }
  }

  private func restore(_ row: JunkReviewRow) {
    if review.blockingRule(for: row) == nil {
      review.restore(row)
    } else {
      confirmingRestore = true
    }
  }
}

private struct JunkPager: View {
  let review: JunkReviewModel

  var body: some View {
    HStack {
      Button("Previous Page") { review.showPage(review.pageIndex - 1) }
        .disabled(!review.hasPreviousPage || review.loading.isBusy)
      if review.hasLoaded {
        Text("Page \(review.pageIndex + 1) of \(review.pageCount)").foregroundStyle(.secondary)
      }
      Button("Next Page") { review.showPage(review.pageIndex + 1) }
        .disabled(!review.hasNextPage || review.loading.isBusy)
      if review.loading.isBusy { ProgressView().controlSize(.small) }
    }
  }
}

extension JunkProvenance {
  var localizedDescription: String {
    switch self {
      case .spamWise(let reason):
        String(localized: "SpamWise moved this message to Junk: \(reason.localizedDescription)")
      case .userCorrection: String(localized: "You marked this message as Junk.")
      case .elsewhere:
        String(
          localized:
            "SpamWise didn’t put this message in Junk. Another filter or the mail server did."
        )
      case .unknown:
        String(
          localized: """
            SpamWise has no record of this message. It may have arrived before SpamWise started, \
            or another filter or the mail server moved it.
            """
        )
    }
  }
}

private extension SenderRule {
  /// What restoring a message from a sender this Block rule matches does to the rule.
  func restoreConsequence(sender: String) -> String {
    scope == .address
      ? String(
        localized: "Marking it as Good replaces your Block rule for \(value) with an Allow rule."
      )
      : String(
        localized: "Your Block rule for \(value) stays, but mail from \(sender) will be allowed."
      )
  }
}

/// A message’s text in its own sheet.
struct MessagePreviewSheet: View {
  let preview: MessagePreview
  @Environment(\.dismiss)
  private var dismiss

  var body: some View {
    NavigationStack {
      MessageTextView(text: preview.text)
        .navigationTitle("Message Preview")
        .toolbar { DoneToolbarItem(dismiss: dismiss, identifier: "preview.done") }
    }
    .frame(minWidth: 560, minHeight: 400)
  }
}

/// A message’s plain text, selectable and scrollable.
struct MessageTextView: View {
  let text: String

  var body: some View {
    ScrollView {
      Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
  }
}

#Preview("No account") { MailReviewView(review: PreviewHelper.model().junkReview) }
#Preview("Junk page") { MailReviewView(review: PreviewHelper.junkReview()) }
#Preview("Plain-text preview") {
  MessagePreviewSheet(preview: MessagePreview(text: "A safe local message preview."))
}
