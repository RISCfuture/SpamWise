import Foundation
import Network
import NIOCore
import NIOIMAP
import NIOTransportServices

/// A connected channel whose pipeline decodes IMAP responses into an ordered, bounded stream.
struct IMAPConnection: Sendable {
  /// The connection's NIO channel; writes accept `IMAPClientHandler.Message` values.
  let channel: any Channel
  /// Decoded responses in arrival order; the stream fails with an ``IMAPError`` on protocol errors.
  let responses: AsyncThrowingStream<Response, any Error>
}

/// Opens implicit-TLS IMAP connections and installs the bounded response pipeline.
enum IMAPPipeline {
  /// Connections close this long after they are established, whatever they are doing.
  static let sessionLifetime = TimeAmount.seconds(30)
  /// Largest accepted message body; matches the adapter's per-message bound.
  static let maximumBodyBytes = 2_000_000
  private static let maximumBufferedResponses = 8192
  private static let maximumFetchAttributes = 16
  private static let parserOptions = ResponseParser.Options(
    messageAttributeLimit: maximumFetchAttributes,
    bodySizeLimit: UInt64(maximumBodyBytes) + 1
  )

  /// Connects with Network.framework TLS, verifying the certificate chain and hostname; plaintext and STARTTLS are unsupported.
  static func connectTLS(_ configuration: IMAPConfiguration) async throws -> IMAPConnection {
    try configuration.validate()
    do {
      return try await NIOTSConnectionBootstrap(group: NIOTSEventLoopGroup.singleton)
        .connectTimeout(sessionLifetime)
        .tlsOptions(NWProtocolTLS.Options())
        .connect(host: configuration.host, port: Int(configuration.port)) { channel in
          channel.eventLoop.makeCompletedFuture { try configure(channel) }
        }
    } catch {
      throw IMAPError.unavailable
    }
  }

  /// Installs IMAP framing and the response stream, and schedules the session cutoff. Runs on the channel's event loop.
  static func configure(_ channel: any Channel) throws -> IMAPConnection {
    let (responses, continuation) = AsyncThrowingStream.makeStream(
      of: Response.self,
      bufferingPolicy: .bufferingOldest(maximumBufferedResponses)
    )
    continuation.onTermination = { _ in channel.close(promise: nil) }
    try channel.pipeline.syncOperations.addHandlers(
      IMAPLineEndingCoalescer(),
      IMAPClientHandler(parserOptions: parserOptions),
      IMAPResponseForwarder(continuation: continuation)
    )
    channel.eventLoop.scheduleTask(in: sessionLifetime) { channel.close(promise: nil) }
    return IMAPConnection(channel: channel, responses: responses)
  }
}

/// Delivers a chunk's trailing CR together with the bytes that follow it.
///
/// The response parser accepts a lone CR after a literal's `{size}` as the complete line ending, so
/// a CRLF split across reads would otherwise make the LF the literal's first byte.
private final class IMAPLineEndingCoalescer: ChannelInboundHandler {
  typealias InboundIn = ByteBuffer
  typealias InboundOut = ByteBuffer

  private static let carriageReturn = UInt8(ascii: "\r")
  private var holdsCarriageReturn = false

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    var chunk = unwrapInboundIn(data)
    guard chunk.readableBytes > 0 else { return }
    if holdsCarriageReturn {
      var joined = context.channel.allocator.buffer(capacity: chunk.readableBytes + 1)
      joined.writeInteger(Self.carriageReturn)
      joined.writeBuffer(&chunk)
      chunk = joined
    }
    holdsCarriageReturn = chunk.readableBytesView.last == Self.carriageReturn
    if holdsCarriageReturn { chunk.moveWriterIndex(to: chunk.writerIndex - 1) }
    guard chunk.readableBytes > 0 else { return }
    context.fireChannelRead(wrapInboundOut(chunk))
  }
}

/// Forwards decoded responses to the session and closes the channel on any protocol failure.
private final class IMAPResponseForwarder: ChannelInboundHandler {
  typealias InboundIn = Response

  private let continuation: AsyncThrowingStream<Response, any Error>.Continuation

  init(continuation: AsyncThrowingStream<Response, any Error>.Continuation) {
    self.continuation = continuation
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    if case .dropped = continuation.yield(unwrapInboundIn(data)) {
      fail(IMAPError.limitExceeded, context: context)
    }
  }
  func errorCaught(context: ChannelHandlerContext, error: any Error) {
    fail(IMAPError(connectionFailure: error), context: context)
  }
  func channelInactive(context: ChannelHandlerContext) {
    continuation.finish()
    context.fireChannelInactive()
  }
  private func fail(_ error: IMAPError, context: ChannelHandlerContext) {
    continuation.finish(throwing: error)
    context.close(promise: nil)
  }
}
