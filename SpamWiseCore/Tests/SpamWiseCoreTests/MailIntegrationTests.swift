import Foundation
import Testing
import SpamWiseCore
import MailIntegration
@Test func appleScriptLiteralsCannotBecomeCommands() {
    #expect(MailScripts.literal("a\" & do shell script \"bad") == "\"a\\\" & do shell script \\\"bad\"")
    #expect(MailScripts.literal("a\\b").contains("a\\\\b"))
    #expect(!MailScripts.literal("a\nb").contains("\n"))
}
@Test func scriptsRequireAccountScopedIdentityAndExactSource() throws {
    #expect(throws: IntegrationError.self) { try MailScripts.lookup(.init(accountID: nil, contentHash: "x")) }
    let identity = MessageIdentity(accountID: "account", messageID: "<id>", contentHash: "x")
    let script = try MailScripts.lookup(identity, action: .moveToJunk, expectedSource: "safe source")
    #expect(script.contains("count of matches) is not 1"))
    #expect(script.contains("source of targetMessage"))
    #expect(script.contains("mailboxes of junk mailbox"))
}
actor StubAppleEvents: AppleEventRunner {
    let response: ScriptValue
    init(_ response: ScriptValue) { self.response = response }
    func run(_ source: String) async throws -> ScriptValue { response }
}
@Test func adapterRejectsChangedSource() async throws {
    let runner = StubAppleEvents(.list([.string("account"), .string("Inbox"), .integer(1), .string("id"), .string("changed")]))
    let adapter = AppleMailAdapter(runner: runner)
    do { _ = try await adapter.lookup(.init(accountID: "account", messageID: "id", contentHash: "expected")); Issue.record("Expected stale message rejection") }
    catch { #expect(error as? IntegrationError == .staleMessage) }
}
@Test func completionInvokesExactlyOnce() async {
    let count = Counter()
    let completion = CompletionOnce<Int> { _ in count.increment() }
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<100 { group.addTask { completion.finish(1) } }
    }
    #expect(count.value == 1)
}
import Synchronization
final class Counter: Sendable {
    private let storage = Mutex(0)
    var value: Int { storage.withLock { $0 } }
    func increment() { storage.withLock { $0 += 1 } }
}
@Test @MainActor func generatedScriptsCompileWithoutExecutingMailActions() throws {
    let identity = MessageIdentity(accountID: "test-account", messageID: "test-id", contentHash: "test")
    let scripts = [MailScripts.accounts, MailScripts.selected, MailScripts.recent(limit: 5), try MailScripts.lookup(identity), try MailScripts.lookup(identity, action: .moveToJunk, expectedSource: "From: x\n\nbody")]
    for source in scripts {
        let script = try #require(NSAppleScript(source: source))
        var error: NSDictionary?
        let compiled = script.compileAndReturnError(&error)
        #expect(compiled, Comment(rawValue: error?.description ?? "Script compiles"))
    }
}
