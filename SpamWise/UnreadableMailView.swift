import SwiftUI

struct UnreadableMailView: View {
  let count: Int

  var body: some View {
    if count > 0 {
      LabeledContent("Unreadable messages", value: count.formatted())
      Text("Unreadable mail stays in place and is retried on the next sweep.")
        .foregroundStyle(.secondary)
    }
  }
}

#Preview("Incomplete sweep") {
  Form { UnreadableMailView(count: 3) }.formStyle(.grouped).frame(width: 600, height: 180)
}
#Preview("Readable sweep") {
  Form { UnreadableMailView(count: 0) }.formStyle(.grouped).frame(width: 600, height: 180)
}
