import SwiftUI
import SpamWiseCore

struct ReviewDigestView: View {
  @Bindable var model: AppModel
  @State private var selection: UUID?
  @State private var showsDecision = false
  private var records: [DecisionRecord] { ReviewDigest(state: model.state).records }

  var body: some View {
    VStack(alignment: .leading) {
      Text("Weekly Review digest").font(.headline).padding([.top, .horizontal])
      if records.isEmpty {
        ContentUnavailableView(
          "Nothing to review",
          systemImage: "tray",
          description: Text("No unresolved Review items in the last seven days.")
        )
      } else {
        List(records) { record in
          VStack(alignment: .leading) {
            Text(record.displaySubject).font(.headline)
            Text(record.displaySender).foregroundStyle(.secondary)
            Text(record.decision.reason.localizedDescription)
            Text(ReviewPriority.reason(record)).foregroundStyle(.secondary)
            Button("Review decision") {
              selection = record.id; showsDecision = true
            }
          }
        }
      }
      HStack {
        Spacer()
        Button("Done") { model.showDigest = false }.keyboardShortcut(.defaultAction)
      }.padding([.horizontal, .bottom])
    }.frame(minWidth: 480, idealWidth: 600, minHeight: 340, idealHeight: 450)
      .sheet(isPresented: $showsDecision) {
        VStack {
          if let record = model.state.records.first(where: { $0.id == selection }) {
            DecisionDetailView(model: model, row: record)
          }
          Button("Done") { showsDecision = false }.padding()
        }.frame(minWidth: 520, minHeight: 500)
      }
  }
}

#Preview("Digest") { ReviewDigestView(model: PreviewHelper.model()) }
#Preview("Empty digest") { ReviewDigestView(model: PreviewHelper.model(empty: true)) }
