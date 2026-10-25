import SwiftUI
import SpamWiseCore

/// This week's unresolved Review items; a decision opens within the digest, not over it.
struct ReviewDigestView: View {
  let activity: ActivityModel
  let shared: SharedStateModel
  let corrections: CorrectionsModel
  let messages: MessageAccessModel
  @State private var digest: ReviewDigest?
  @State private var path: [DigestRoute] = []
  @State private var loadFailure: OperationFailure?
  @Environment(\.dismiss)
  private var dismiss

  var body: some View {
    NavigationStack(path: $path) {
      DigestList(records: digest?.records, failure: loadFailure)
        .navigationTitle("Weekly Review Digest")
        .toolbar { DoneToolbarItem(dismiss: dismiss, identifier: "digest.done") }
        .navigationDestination(for: DigestRoute.self) { route in
          switch route {
            case .decision(let id):
              if let record = digest?.records.first(where: { $0.id == id }) {
                DecisionDetailView(
                  row: record,
                  corrections: corrections,
                  messages: messages,
                  shared: shared,
                  activity: activity
                ) { path.append(.preview($0)) }
                .navigationTitle(record.displaySubject)
              }
            case .preview(let preview):
              MessageTextView(text: preview.text).navigationTitle("Message Preview")
          }
        }
    }
    .frame(minWidth: 520, idealWidth: 600, minHeight: 420, idealHeight: 500)
    .task(id: shared.recordsVersion) { await load() }
  }

  private func load() async {
    do {
      let loaded = try await activity.digest()
      digest = loaded
      loadFailure = nil
      await shared.markDigestSeen(loaded)
    } catch {
      loadFailure = OperationFailure(error)
    }
  }
}

/// A screen pushed inside the digest.
enum DigestRoute: Hashable {
  case decision(UUID)
  case preview(MessagePreview)
}

private struct DigestList: View {
  let records: [DecisionRecord]?
  let failure: OperationFailure?

  var body: some View {
    if let failure {
      StatusLabel(status: .failure(failure)).padding()
    } else if let records, records.isEmpty {
      ContentUnavailableView(
        "Nothing to review",
        systemImage: "tray",
        description: Text(
          "No unresolved Review items in the last \(ReviewDigest.lookbackDays) days."
        )
      )
    } else if let records {
      List(records) { record in
        NavigationLink(value: DigestRoute.decision(record.id)) {
          VStack(alignment: .leading) {
            Text(record.displaySubject).font(.headline)
            Text(record.displaySender).foregroundStyle(.secondary)
            Text(record.decision.reason.localizedDescription)
            Text(ReviewPriority.reason(record)).foregroundStyle(.secondary)
          }
        }
      }
    } else {
      ProgressView()
    }
  }
}

#Preview("Digest") {
  let model = PreviewHelper.model()
  ReviewDigestView(
    activity: model.activity,
    shared: model.shared,
    corrections: model.corrections,
    messages: model.messages
  )
}
#Preview("Empty digest") {
  let model = PreviewHelper.model(empty: true)
  ReviewDigestView(
    activity: model.activity,
    shared: model.shared,
    corrections: model.corrections,
    messages: model.messages
  )
}
