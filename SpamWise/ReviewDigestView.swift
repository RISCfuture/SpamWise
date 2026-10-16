import SwiftUI
import SpamWiseCore

struct ReviewDigestView: View {
  @Bindable var model: AppModel
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
            Text(record.subject).font(.headline)
            Text(record.sender).foregroundStyle(.secondary)
            Text(record.decision.reason)
          }
        }
      }
      HStack {
        Spacer()
        Button("Done") { model.showDigest = false }.keyboardShortcut(.defaultAction)
      }.padding([.horizontal, .bottom])
    }.frame(minWidth: 480, idealWidth: 600, minHeight: 340, idealHeight: 450)
  }
}

#Preview("Digest") { ReviewDigestView(model: PreviewHelper.model()) }
#Preview("Empty digest") { ReviewDigestView(model: PreviewHelper.model(empty: true)) }
