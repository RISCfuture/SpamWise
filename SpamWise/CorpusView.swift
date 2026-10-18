import SwiftUI
import UniformTypeIdentifiers
import SpamWiseCore

struct CorpusView: View {
  let model: AppModel
  @State private var selection: String?
  @State private var label: MailLabel = .inbox
  @State private var importing = false
  @State private var exporting = false
  @State private var export: RulesDocument?
  @Environment(\.dismiss) private var dismiss

  private var labels: [ReviewedLabel] {
    model.state.reviewedLabels.sorted { $0.date > $1.date }
  }
  private var selected: ReviewedLabel? { labels.first { $0.id == selection } }
  var body: some View {
    VStack(alignment: .leading) {
      Text("Reviewed corpus").font(.title2).accessibilityIdentifier("corpus.title")
      Text(
        "Import only messages you reviewed. Mailbox membership and SpamSieve predictions are not human labels."
      )
      .foregroundStyle(.secondary)
      HStack {
        ForEach(MailLabel.allCases, id: \.self) { kind in
          Text("\(kind.localizedTitle): \(labels.filter { $0.label == kind }.count)")
        }
        Spacer()
        Text("Held out: \(labels.filter(\.heldOut).count)")
      }
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
      HStack {
        Picker("Reviewed label", selection: $label) {
          ForEach(MailLabel.allCases, id: \.self) { Text($0.localizedTitle).tag($0) }
        }.frame(maxWidth: 230)
        Button("Import reviewed .eml files…") { importing = true }
        Button("Relabel") { relabel() }.disabled(selected == nil)
        Button("Forget", role: .destructive) { forget() }.disabled(selected == nil)
          .accessibilityIdentifier("corpus.forget")
      }.disabled(model.busy)
      HStack {
        Button("Export reviewed corpus") {
          if let data = try? JSONEncoder.pretty.encode(labels) {
            export = RulesDocument(data: data); exporting = true
          }
        }
        Spacer()
        Button("Done") { dismiss() }.accessibilityIdentifier("corpus.done")
      }
      if !model.status.isEmpty { Text(model.status).foregroundStyle(.secondary) }
    }.padding().frame(minWidth: 760, minHeight: 450)
      .fileImporter(
        isPresented: $importing,
        allowedContentTypes: [.data],
        allowsMultipleSelection: true
      ) {
        if case .success(let urls) = $0 { importFiles(urls) }
      }
      .fileExporter(
        isPresented: $exporting,
        document: export,
        contentType: .json,
        defaultFilename: "SpamWise-reviewed"
      ) {
        if case .failure = $0 { model.status = String(localized: "Corpus export failed.") }
      }
  }
  private func importFiles(_ urls: [URL]) {
    let chosenLabel = label
    model.run {
      guard let store = model.store, urls.count <= 20 else { throw ParseError.tooLarge }
      var messages: [ParsedMessage] = []
      for url in urls {
        try Task.checkCancellation()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: 2_000_001) ?? Data()
        messages.append(try MIMEParser().parse(data))
      }
      try await CorpusManagement.importMessages(messages, label: chosenLabel, store: store)
      model.status = String(
        localized: "Reviewed examples imported. No sender rules or mail actions were created."
      )
    }
  }
  private func forget() {
    guard let selected else { return }
    model.run {
      guard let store = model.store else { throw IntegrationError.unavailable }
      try await CorpusManagement.forget(id: selected.id, store: store)
    }
  }
  private func relabel() {
    guard let selected else { return }
    let chosenLabel = label
    model.run {
      guard let store = model.store else { throw IntegrationError.unavailable }
      try await CorpusManagement.relabel(id: selected.id, label: chosenLabel, store: store)
    }
  }
}

#Preview("Reviewed corpus") { CorpusView(model: PreviewHelper.model()) }
