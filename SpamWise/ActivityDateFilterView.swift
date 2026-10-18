import SwiftUI
import SpamWiseCore

struct ActivityDateFilterView: View {
  @Binding var query: ActivityQuery
  @State private var start = Date.now
  @State private var end = Date.now
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        DatePicker("From", selection: $start, displayedComponents: .date)
        DatePicker("Through", selection: $end, displayedComponents: .date)
      }
      .formStyle(.grouped)
      .navigationTitle("Date range")
      .toolbar {
        ConfirmationToolbarItems(
          confirmTitle: "Apply dates",
          canConfirm: start <= end,
          cancel: { dismiss() },
          confirm: apply
        )
      }
    }
    .frame(minWidth: 360)
    .onAppear {
      start = query.start ?? Calendar.current.startOfDay(for: .now)
      end = query.end ?? .now
    }
  }

  private func apply() {
    let calendar = Calendar.current
    query.start = calendar.startOfDay(for: start)
    let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end))
    query.end = nextDay?.addingTimeInterval(-0.001)
    dismiss()
  }
}

#Preview { ActivityDateFilterView(query: .constant(ActivityQuery())) }
