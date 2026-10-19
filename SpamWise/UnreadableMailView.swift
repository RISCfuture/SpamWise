import SwiftUI

struct UnreadableMailView: View {
  let messageCount: Int

  var body: some View {
    if messageCount > 0 {
      LabeledContent("Unreadable messages", value: messageCount.formatted())
      Text("SpamWise leaves these in place and tries them again at the next check.")
        .foregroundStyle(.secondary)
    }
  }
}

#Preview("Incomplete sweep") {
  Form { UnreadableMailView(messageCount: 3) }.formStyle(.grouped).frame(width: 600, height: 180)
}
#Preview("Readable sweep") {
  Form { UnreadableMailView(messageCount: 0) }.formStyle(.grouped).frame(width: 600, height: 180)
}
