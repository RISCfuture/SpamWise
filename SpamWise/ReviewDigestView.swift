import SwiftUI
import SpamWiseCore

/**
 This week's unresolved Review items; a decision opens within the digest, not over it.

 An opened decision stays open after a correction resolves it and the digest drops it, so its
 status and follow-up prompts remain visible.
 */
struct ReviewDigestView: View {
  let activity: ActivityModel
  let shared: SharedStateModel
  let corrections: CorrectionsModel
  let messages: MessageAccessModel
  @State private var digest: ReviewDigest?
  @State private var path: [DigestRoute] = []
  /// Decisions opened from the digest, refreshed from the store on each reload.
  @State private var opened: [UUID: DecisionRecord] = [:]
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
              if let record = digest?.records.first(where: { $0.id == id }) ?? opened[id] {
                DecisionDetailView(
                  row: record,
                  corrections: corrections,
                  messages: messages,
                  shared: shared,
                  activity: activity
                ) { path.append(.preview($0)) }
                .navigationTitle(record.displaySubject)
              } else {
                ContentUnavailableView(
                  "Decision Unavailable",
                  systemImage: "tray",
                  description: Text("Activity no longer keeps this decision.")
                )
              }
            case .preview(let preview):
              MessageTextView(text: preview.text).navigationTitle("Message Preview")
          }
        }
    }
    .frame(minWidth: 520, idealWidth: 600, minHeight: 420, idealHeight: 500)
    .task(id: shared.recordsVersion) { await load() }
    .onChange(of: path) { _, path in remember(path) }
  }

  private func load() async {
    do {
      let loaded = try await activity.digest()
      digest = loaded
      loadFailure = nil
      await refreshOpened()
      await shared.markDigestSeen(loaded)
    } catch {
      loadFailure = OperationFailure(error)
    }
  }

  /// Keeps each decision pushed onto `path`, so it outlasts the digest dropping it.
  private func remember(_ path: [DigestRoute]) {
    for case .decision(let id) in path where opened[id] == nil {
      opened[id] = digest?.records.first { $0.id == id }
    }
  }

  /// Rereads the opened decisions, keeping the previous copy of any the store no longer returns.
  private func refreshOpened() async {
    for id in opened.keys {
      if let record = await activity.storedRecord(id: id) { opened[id] = record }
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
      ProgressView { Text("Loading the Review digest…") }.labelsHidden()
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
