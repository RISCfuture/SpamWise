import Foundation
import SwiftData
@Model final class Row {
  @Attribute(.unique) var key: String
  init(_ key: String) { self.key = key }
}
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let container = try ModelContainer(
  for: Row.self,
  configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
)
let context = ModelContext(container)
context.autosaveEnabled = false
if CommandLine.arguments.count > 2 {
  let prefix = CommandLine.arguments[2]
  for i in 0..<50 {
    context.insert(Row("\(prefix)-\(i)"))
    try context.save()
  }
}
print(try ModelContext(container).fetchCount(FetchDescriptor<Row>()))
