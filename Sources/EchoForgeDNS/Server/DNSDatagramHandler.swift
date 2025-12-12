//
//  DNSDatagramHandler.swift
//  EchoForgeDNS
//
//  Created by MagicianQuinn on 2025/12/11.
//

import DNSClient
import Network
import NIO

/// UDP Handler
final class DNSDatagramHandler: ChannelInboundHandler {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>
    typealias OutboundOut = AddressedEnvelope<ByteBuffer>

    private let router: DNSRouter

    init(router: DNSRouter) {
        self.router = router
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = unwrapInboundIn(data)
        let buffer = envelope.data

        guard let queryMessage = try? DNSDecoder.parse(buffer) else {
            print("Failed to parse DNS message")
            return
        }

        guard !queryMessage.header.options.contains(.answer) else {
            print("Received DNS response instead of query")
            return
        }

        guard let question = queryMessage.questions.first else {
            print("No questions in DNS query")
            return
        }

        let domain = question.labels.string
        let queryType = question.type

        print("DNS Query: \(domain) type: \(queryType)")

        // Use NIO-friendly EventLoopFuture flow: ask the router for a future,
        // then encode and write on the event loop without capturing ChannelHandlerContext in @Sendable closures.
        let eventLoop = context.eventLoop

        let responseFuture = router.handleInboundFuture(queryMessage, on: eventLoop)

        let encodeFuture = responseFuture.flatMapThrowing { responseMessage -> ByteBuffer in
            var labelIndices = [String: UInt16]()
            let allocator = ByteBufferAllocator()
            return try DNSEncoder.encodeMessage(responseMessage, allocator: allocator, labelIndices: &labelIndices)
        }

        // When encoding completes, schedule the write on the event loop.
        encodeFuture.whenComplete { result in
            switch result {
            case let .success(encodedBuffer):
                eventLoop.execute {
                    let responseEnvelope = AddressedEnvelope(remoteAddress: envelope.remoteAddress, data: encodedBuffer)
                    context.writeAndFlush(self.wrapOutboundOut(responseEnvelope), promise: nil)
                }
            case let .failure(err):
                print("Failed to encode DNS response: \(err)")
            }
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("DNSHandler error: \(error)")
        context.close(promise: nil)
    }
}

// DNSDatagramHandler intentionally does not declare Sendable conformance.

// Pragmatic: mark handler as unchecked Sendable to suppress warnings about
// capturing non-Sendable NIO types in @Sendable closures. This is safe here
// because all Channel I/O is scheduled on the channel's EventLoop.
extension DNSDatagramHandler: @unchecked Sendable {}

// Also mark ChannelHandlerContext as unchecked Sendable to avoid warnings
// when scheduling eventLoop.execute closures that reference the context.
extension ChannelHandlerContext: @unchecked Sendable {}
