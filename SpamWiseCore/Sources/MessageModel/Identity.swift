import Foundation
public struct MessageIdentity: Codable, Sendable, Hashable {
    public var accountID: String?
    public var messageID: String?
    public var localID: Int?
    public var mailbox: String?
    public var contentHash: String
    public init(accountID: String?, messageID: String? = nil, localID: Int? = nil, mailbox: String? = nil, contentHash: String) {
        self.accountID = accountID; self.messageID = messageID; self.localID = localID; self.mailbox = mailbox; self.contentHash = contentHash
    }
    public var key: String {
        stableHash(Data([accountID ?? "unresolved", messageID ?? "", contentHash].joined(separator: "\u{0}").utf8))
    }
}
