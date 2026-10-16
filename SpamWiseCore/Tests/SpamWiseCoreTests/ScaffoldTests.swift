import Testing
import SpamWiseCore
@Test func coreModulesAreAvailable() {
    #expect(String(describing: MessageModelModule.self) == "MessageModelModule")
    #expect(String(describing: StoreModule.self) == "StoreModule")
}
