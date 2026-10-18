import SwiftUI
import UniformTypeIdentifiers
import SpamWiseCore

struct CorpusView: View {
  let corpus: CorpusModel
  @State private var selection: String?
  @State private var label: MailLabel = .inbox
  @State private var importing = false
  @State private var exporting = false
  @State private var export: RulesDocument?
  @State private var exportStatus: OperationStatus?
  @Environment(\.dismiss) private var dismiss

  private var labels: [ReviewedLabel] { corpus.labels }
  private var selected: ReviewedLabel? { labels.first { $0.id == selection } }

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading) {
        Text(
          "Import only messages you reviewed. Mailbox membership and SpamSieve predictions are not human labels."
        )
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("corpus.title")
        HStack {
          ForEach(MailLabel.allCases, id: \.self) { kind in
            Text("\(kind.localizedTitle): \(labels.filter { $0.label == kind }.count)")
          }
          Spacer()
          Text("Held out: \(labels.filter(\.heldOut).count)")
        }
        CorpusTable(labels: labels, selection: $selection)
        HStack {
          Picker("Reviewed label", selection: $label) {
            ForEach(MailLabel.allCases, id: \.self) { Text($0.localizedTitle).tag($0) }
          }.frame(maxWidth: 230)
          Button("Import reviewed .eml files…") { importing = true }
          Button("Relabel") { if let selected { corpus.relabel(selected.id, as: label) } }
            .disabled(selected == nil)
          Button("Forget", role: .destructive) { if let selected { corpus.forget(selected.id) } }
            .disabled(selected == nil)
            .accessibilityIdentifier("corpus.forget")
          if corpus.operation.isBusy { ProgressView().controlSize(.small) }
        }
        HStack {
          Button("Export reviewed corpus") { exportCorpus() }.disabled(labels.isEmpty)
          Spacer()
        }
        OperationStatusView(operation: corpus.operation)
        StatusLabel(status: exportStatus)
      }
      .padding()
      .navigationTitle("Reviewed corpus")
      .toolbar { DoneToolbarItem(dismiss: dismiss, identifier: "corpus.done") }
    }
    .frame(minWidth: 760, minHeight: 450)
    .fileImporter(
      isPresented: $importing,
      allowedContentTypes: [.data],
      allowsMultipleSelection: true
    ) {
      if case .success(let urls) = $0 { corpus.importMessages(urls, label: label) }
    }
    .fileExporter(
      isPresented: $exporting,
      document: export,
      contentType: .json,
      defaultFilename: "SpamWise-reviewed"
    ) { exportStatus = ExportResult.status(of: $0, failure: "Corpus export failed.") }
  }

  private func exportCorpus() {
    do {
      export = RulesDocument(data: try corpus.exported()); exporting = true
    } catch {
      exportStatus = .failure(OperationFailure(error))
    }
  }
}

private struct CorpusTable: View {
  let labels: [ReviewedLabel]
  @Binding var selection: String?

  var body: some View {
    Table(labels, selection: $selection) {
      TableColumn("Subject") { Text($0.message?.displaySubject ?? String($0.id.prefix(12))) }
      TableColumn("Label") {
        Text($0.label.localizedTitle).accessibilityIdentifier("corpus.label.\($0.id)")
      }
      TableColumn("Partition") { Text($0.heldOut ? "Held out" : "Training") }
      TableColumn("Source") {
        Text($0.origin == .reviewedImport ? "Reviewed import" : "Correction")
      }
      TableColumn("Content") { Text($0.message == nil ? "Not retained" : "Retained locally") }
    }
    .overlay {
      if labels.isEmpty {
        ContentUnavailableView(
          "No reviewed examples",
          systemImage: "tray",
          description: Text("Corrections and imported reviewed messages appear here.")
        )
      }
    }
  }
}

#Preview("Reviewed corpus") { CorpusView(corpus: PreviewHelper.model().corpus) }
