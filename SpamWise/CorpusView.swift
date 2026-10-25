import SwiftUI
import UniformTypeIdentifiers
import SpamWiseCore

/// The messages SpamWise learns from: the user’s corrections and imported reviewed messages.
struct CorpusView: View {
  let corpus: CorpusModel
  @State private var selection: Set<String> = []
  @State private var importLabel: MailLabel = .junk
  @State private var importing = false
  @State private var pendingImport: [URL]?
  @State private var forgetting: Set<String> = []
  @State private var exporting = false
  @State private var export: RulesDocument?
  @State private var exportStatus: OperationStatus?
  @Environment(\.dismiss)
  private var dismiss

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading) {
        HStack {
          Text(
            "SpamWise learns from messages you’ve checked yourself. Importing them never creates rules or moves mail."
          )
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("corpus.title")
          Spacer()
          HelpButton(page: "reviewed-messages-and-learning")
        }
        CorpusSummary(corpus: corpus)
        CorpusTable(
          labels: corpus.labels,
          selection: $selection,
          relabel: { corpus.relabel($0, as: $1) },
          forget: { forgetting = $0 }
        )
        CorpusActions(
          corpus: corpus,
          selection: selection,
          importLabel: $importLabel,
          chooseFiles: { importing = true },
          forget: { forgetting = selection },
          export: exportCorpus
        )
        OperationStatusView(operation: corpus.operation)
        StatusLabel(status: exportStatus)
      }
      .padding()
      .navigationTitle("Reviewed Messages")
      .toolbar { DoneToolbarItem(dismiss: dismiss, identifier: "corpus.done") }
    }
    .frame(minWidth: 760, minHeight: 450)
    .fileImporter(
      isPresented: $importing,
      allowedContentTypes: [.emailMessage],
      allowsMultipleSelection: true
    ) {
      if case .success(let urls) = $0 { requestImport(urls) }
    }
    .fileExporter(
      isPresented: $exporting,
      document: export,
      contentType: .json,
      defaultFilename: "SpamWise-reviewed"
    ) {
      exportStatus = ExportResult.status(of: $0, failure: "Reviewed messages couldn’t be exported.")
    }
    .confirmationDialog(
      "Forget \(forgetting.count) reviewed messages?",
      isPresented: Binding(get: { !forgetting.isEmpty }, set: { if !$0 { forgetting = [] } })
    ) {
      Button("Forget", role: .destructive) {
        corpus.forget(forgetting)
        selection.subtract(forgetting)
      }
      .accessibilityIdentifier("corpus.forget.confirm")
    } message: {
      Text("SpamWise also forgets what it learned from them. Your sender rules stay.")
    }
    .confirmationDialog(
      "Import over older corrections?",
      isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })
    ) {
      Button("Import") {
        if let pendingImport { corpus.importMessages(pendingImport, label: importLabel) }
      }
    } message: {
      Text(
        "To stay within \(corpus.capacity.limit) examples, SpamWise forgets up to \(corpus.correctionsDisplaced(importing: pendingImport?.count ?? 0)) of your oldest corrections as learning examples. Your sender rules stay."
      )
    }
  }

  private func requestImport(_ urls: [URL]) {
    if corpus.correctionsDisplaced(importing: urls.count) > 0 {
      pendingImport = urls
    } else {
      corpus.importMessages(urls, label: importLabel)
    }
  }

  private func exportCorpus() {
    do {
      export = RulesDocument(data: try corpus.exported()); exporting = true
    } catch {
      exportStatus = .failure(OperationFailure(error))
    }
  }
}

/// Counts by label and how much room is left.
private struct CorpusSummary: View {
  let corpus: CorpusModel

  var body: some View {
    let capacity = corpus.capacity, labels = corpus.labels
    HStack {
      ForEach(MailLabel.allCases, id: \.self) { kind in
        Text("\(kind.reviewedTitle): \(labels.filter { $0.label == kind }.count)")
      }
      Spacer()
      Text(
        "\(capacity.imported + capacity.corrections) of \(capacity.limit) kept. You can import \(capacity.remainingImports) more."
      )
      .foregroundStyle(.secondary)
    }
  }
}

private struct CorpusActions: View {
  let corpus: CorpusModel
  let selection: Set<String>
  @Binding var importLabel: MailLabel
  let chooseFiles: () -> Void
  let forget: () -> Void
  let export: () -> Void

  var body: some View {
    HStack {
      Picker("Import as", selection: $importLabel) {
        ForEach(MailLabel.allCases, id: \.self) { Text($0.reviewedTitle).tag($0) }
      }
      .fixedSize()
      Button("Import Messages…", action: chooseFiles)
        .help(Text("Import up to \(CorpusManagement.maximumBatch) .eml files at a time."))
      Menu("Label As") {
        ForEach(MailLabel.allCases, id: \.self) { label in
          Button(label.reviewedTitle) { corpus.relabel(selection, as: label) }
        }
      }
      .fixedSize()
      .disabled(selection.isEmpty)
      Button("Forget…", role: .destructive, action: forget)
        .disabled(selection.isEmpty)
        .accessibilityIdentifier("corpus.forget")
      if corpus.operation.isBusy {
        ProgressView { Text("Updating your reviewed examples…") }.labelsHidden().controlSize(.small)
      }
      Spacer()
      Menu("More") {
        Button("Export Reviewed Messages…", action: export).disabled(corpus.labels.isEmpty)
        Button("Rebuild Learning") { corpus.rebuildLearning() }
          .help(Text("Relearns from the examples listed here and drops anything else."))
      }
      .fixedSize()
    }
  }
}

private struct CorpusTable: View {
  let labels: [ReviewedLabel]
  @Binding var selection: Set<String>
  let relabel: (Set<String>, MailLabel) -> Void
  let forget: (Set<String>) -> Void

  var body: some View {
    Table(labels, selection: $selection) {
      TableColumn("Subject") {
        Text($0.message?.displaySubject ?? String(localized: "Text not kept"))
      }
      TableColumn("Label") {
        Text($0.label.reviewedTitle).accessibilityIdentifier("corpus.label.\($0.id)")
      }
      TableColumn("Source") {
        Text($0.origin == .reviewedImport ? "Imported" : "Your correction")
      }
    }
    .contextMenu(forSelectionType: String.self) { ids in
      if !ids.isEmpty {
        Menu("Label As") {
          ForEach(MailLabel.allCases, id: \.self) { label in
            Button(label.reviewedTitle) { relabel(ids, label) }
          }
        }
        Button("Forget…", role: .destructive) { forget(ids) }
      }
    }
    .onDeleteCommand { if !selection.isEmpty { forget(selection) } }
    .overlay {
      if labels.isEmpty {
        ContentUnavailableView(
          "No Reviewed Messages",
          systemImage: "tray",
          description: Text("Your corrections and the messages you import appear here.")
        )
      }
    }
  }
}

extension MailLabel {
  /// The verdict noun for a reviewed label: Good, Junk or Review.
  var reviewedTitle: String {
    switch self {
      case .inbox: String(localized: "Good")
      case .junk: String(localized: "Junk")
      case .review: String(localized: "Review")
    }
  }
}

#Preview("Reviewed messages") { CorpusView(corpus: PreviewHelper.model().corpus) }
#Preview("With examples") { CorpusView(corpus: PreviewHelper.model(reviewed: true).corpus) }
