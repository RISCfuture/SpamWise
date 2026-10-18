import Foundation
import NIOCore
import NIOIMAP

/// The untagged data and completion text a server returned for one command.
struct IMAPReply {
  /// Untagged responses other than FETCH data.
  var untagged: [ResponsePayload] = []
  /// Completed FETCH responses, each with at most one complete body.
  var fetches: [IMAPFetch] = []
  /// The text of the tagged OK completion.
  var completion = ResponseText(text: "")

  /// Response codes from untagged OK status responses and from the tagged completion.
  var codes: [ResponseTextCode] {
    untagged.compactMap { payload -> ResponseTextCode? in
      if case .conditionalState(.ok(let text)) = payload { text.code } else { nil }
    } + [completion.code].compactMap(\.self)
  }

  /// Accumulates a reply while enforcing per-command response and byte bounds.
  struct Builder {
    private let maximumResponses: Int
    private let maximumBytes: Int
    private var reply = IMAPReply()
    private var fetch: IMAPFetch?
    private var body: Data?
    private var expectedBodyBytes = 0
    private var responses = 0
    private var bytes = 0

    init(maximumResponses: Int, maximumBytes: Int) {
      self.maximumResponses = maximumResponses; self.maximumBytes = maximumBytes
    }

    mutating func append(_ payload: ResponsePayload) throws {
      guard fetch == nil else { throw IMAPError.malformedResponse }
      try count()
      reply.untagged.append(payload)
    }

    mutating func append(_ part: FetchResponse) throws {
      switch part {
        case .start(let sequence):
          try begin(IMAPFetch(sequence: Int(sequence)))
        case .startUID(let uid):
          try begin(IMAPFetch(uid: Int(uid)))
        case .simpleAttribute(let attribute):
          guard fetch != nil, body == nil else { throw IMAPError.malformedResponse }
          try fetch?.record(attribute)
        case .streamingBegin(.body(let section, nil), let byteCount) where section == .complete:
          try beginBody(byteCount: byteCount)
        case .streamingBegin: throw IMAPError.malformedResponse
        case .streamingBytes(let buffer): try appendBody(buffer)
        case .streamingEnd: try endBody()
        case .finish:
          guard let fetch, body == nil else { throw IMAPError.malformedResponse }
          reply.fetches.append(fetch)
          self.fetch = nil
      }
    }

    mutating func finish(completion: ResponseText) throws -> IMAPReply {
      guard fetch == nil else { throw IMAPError.malformedResponse }
      reply.completion = completion
      return reply
    }

    private mutating func count() throws {
      responses += 1
      guard responses <= maximumResponses else { throw IMAPError.limitExceeded }
    }
    private mutating func begin(_ next: IMAPFetch) throws {
      guard fetch == nil else { throw IMAPError.malformedResponse }
      try count()
      fetch = next
    }
    private mutating func beginBody(byteCount: Int) throws {
      guard fetch != nil, body == nil, fetch?.body == nil else { throw IMAPError.malformedResponse }
      guard byteCount <= IMAPPipeline.maximumBodyBytes else { throw IMAPError.limitExceeded }
      body = Data(capacity: byteCount); expectedBodyBytes = byteCount
    }
    private mutating func appendBody(_ buffer: ByteBuffer) throws {
      guard body != nil, (body?.count ?? 0) + buffer.readableBytes <= expectedBodyBytes else {
        throw IMAPError.malformedResponse
      }
      bytes += buffer.readableBytes
      guard bytes <= maximumBytes else { throw IMAPError.limitExceeded }
      body?.append(contentsOf: buffer.readableBytesView)
    }
    private mutating func endBody() throws {
      guard let body, body.count == expectedBodyBytes else { throw IMAPError.malformedResponse }
      fetch?.body = body
      self.body = nil
    }
  }
}

/// One FETCH response's identifiers, size, flags and complete body.
struct IMAPFetch {
  /// Message sequence number, absent for UID-only responses.
  var sequence: Int?
  /// Unique identifier within the mailbox's UIDVALIDITY.
  var uid: Int?
  /// Server-reported RFC822.SIZE.
  var size: Int?
  /// Flags after the command, when reported.
  var flags: [Flag]?
  /// The complete `BODY[]` content, when requested.
  var body: Data?

  mutating func record(_ attribute: MessageAttribute) throws {
    switch attribute {
      case .uid(let value):
        guard uid == nil || uid == Int(value) else { throw IMAPError.malformedResponse }
        uid = Int(value)
      case .rfc822Size(let value):
        guard size == nil, value >= 0 else { throw IMAPError.malformedResponse }
        size = value
      case .flags(let value):
        guard flags == nil else { throw IMAPError.malformedResponse }
        flags = value
      default: break
    }
  }
}
