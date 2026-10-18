import SwiftUI

struct UnreadableMailView: View {
  let count: Int

  var body: some View {
    if count > 0 {
      LabeledContent("Unreadable messages", value: count.formatted())
      Text("SpamWise leaves these in place and tries them again at the next check.")
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
