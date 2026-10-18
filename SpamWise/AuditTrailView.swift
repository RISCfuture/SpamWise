import SwiftUI
import SpamWiseCore

struct AuditTrailView: View {
  let model: AppModel
  @State private var search = ""
  @Environment(\.dismiss) private var dismiss

  private var events: [AuditEvent] {
    model.state.auditEvents.reversed().filter {
      search.isEmpty || $0.localizedDescription.localizedCaseInsensitiveContains(search)
    }
  }
  var body: some View {
    VStack {
      TextField("Search configuration history", text: $search)
      Table(events) {
        TableColumn("Time") { Text($0.date.formatted()) }
        TableColumn("Policy revision") { Text($0.revision.formatted()) }.width(90)
        TableColumn("Change", value: \.localizedDescription)
      }
      HStack {
        Spacer(); Button("Done") { dismiss() }
      }
    }.padding().frame(minWidth: 700, minHeight: 420)
  }
}

#Preview("Configuration history") { AuditTrailView(model: PreviewHelper.model()) }
