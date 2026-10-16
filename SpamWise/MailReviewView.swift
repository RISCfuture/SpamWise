import SwiftUI
import SpamWiseCore
import MailIntegration

struct MailReviewView: View {
  @Bindable var model: AppModel
  @State private var accountID = ""
  @State private var offset = 0
  @State private var selection: String?
  @Environment(\.dismiss) private var dismiss

  private var selected: MailEnvelope? { model.junkMessages.first { $0.identity.key == selection } }

  var body: some View {
    VStack(alignment: .leading) {
      Text("Review Junk").font(.title2)
      Text(
        "Folder membership is not a confirmed label. Reading this list does not classify or move mail."
      )
      .foregroundStyle(.secondary)
      HStack {
        Picker("Account", selection: $accountID) {
          Text("Choose account").tag("")
          ForEach(model.accounts) { Text($0.name).tag($0.id) }
        }
        Button("Load page") { model.loadJunk(accountID: accountID, offset: offset) }
          .disabled(accountID.isEmpty || model.busy)
      }
      HSplitView {
        List(model.junkMessages, id: \.identity.key, selection: $selection) { envelope in
          Text(
            (try? MIMEParser().parse(envelope.raw).subject)
              ?? String(localized: "Unclassified message")
          )
          .tag(envelope.identity.key)
        }.frame(minWidth: 220)
        ScrollView {
          Text(
            selected.flatMap { try? MIMEParser().parse($0.raw).text }
              ?? String(localized: "Select a message")
          )
          .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding()
        }.frame(minWidth: 300)
      }
      HStack {
        Button("Previous page") {
          offset = max(0, offset - 20); model.loadJunk(accountID: accountID, offset: offset)
        }
        .disabled(offset == 0 || model.busy)
        Button("Next page") {
          offset += 20; model.loadJunk(accountID: accountID, offset: offset)
        }
        .disabled(offset + 20 >= model.junkTotal || model.busy)
        Spacer()
        Button("Mark Good and restore") {
          if let selected { model.restoreReviewedMessage(selected) }
        }
        .disabled(selected == nil || model.busy)
        Button("Done") { dismiss() }
      }
      if !model.status.isEmpty { Text(model.status).foregroundStyle(.secondary) }
    }.padding().frame(minWidth: 720, minHeight: 480)
      .onChange(of: accountID) { _, _ in
        offset = 0; selection = nil; model.junkMessages = []
      }
  }
}

struct CorrectionResultsView: View {
  let model: AppModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading) {
      Text("Selected-message corrections").font(.title2)
      List(model.correctionResults) { result in
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
      HStack {
        Spacer(); Button("Done") { dismiss() }.disabled(model.busy)
      }
    }.padding().frame(minWidth: 520, minHeight: 320)
  }
}

struct MessagePreviewView: View {
  let text: String
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    VStack {
      ScrollView {
        Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
      }
      HStack {
        Spacer(); Button("Done") { dismiss() }
      }
    }.padding().frame(minWidth: 560, minHeight: 400)
  }
}

#Preview("Junk review") { MailReviewView(model: PreviewHelper.model()) }
#Preview("Corrections") { CorrectionResultsView(model: PreviewHelper.model()) }
#Preview("Plain-text preview") { MessagePreviewView(text: "A safe local message preview.") }
