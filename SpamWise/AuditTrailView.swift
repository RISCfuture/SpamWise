import SwiftUI
import SpamWiseCore

struct AuditTrailView: View {
  let shared: SharedStateModel
  @State private var search = ""
  @Environment(\.dismiss) private var dismiss

  private var events: [AuditEvent] {
    shared.state.auditEvents.reversed().filter {
      search.isEmpty || $0.localizedDescription.localizedCaseInsensitiveContains(search)
    }
  }

  var body: some View {
    NavigationStack {
      Table(events) {
        TableColumn("Time") { Text($0.date.formatted()) }
        TableColumn("Policy revision") { Text($0.revision.formatted()) }.width(90)
        TableColumn("Change", value: \.localizedDescription)
      }
      .overlay {
        if events.isEmpty {
          if search.isEmpty {
            ContentUnavailableView(
              "No configuration changes",
              systemImage: "clock.arrow.circlepath",
              description: Text("Rule, policy and learning changes appear here.")
            )
          } else {
            ContentUnavailableView.search(text: search)
          }
        }
      }
      .navigationTitle("Configuration history")
      .searchable(text: $search, prompt: "Search configuration history")
      .toolbar { DoneToolbarItem(dismiss: dismiss, identifier: "audit.done") }
    }
    .frame(minWidth: 700, minHeight: 420)
  }
}

#Preview("Configuration history") { AuditTrailView(shared: PreviewHelper.model().shared) }
