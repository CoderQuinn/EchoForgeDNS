//
//  DNSRouter.swift
//  EchoForgeDNS
//
//  Created by MagicianQuinn on 2025/12/11.
//

import DNSClient
import Foundation
import Network
import NIO

public final class DNSRouter: @unchecked Sendable {
    public let ipPool: FakeIPPool
    private let upstream: DNSResolverProtocol?
    private let ttl: Int

    public init(upstream: DNSResolverProtocol? = nil, ipPool: FakeIPPool, ttl: Int = 300) {
        self.upstream = upstream
        self.ipPool = ipPool
        self.ttl = ttl
    }

    public func handleInboundFuture(_ message: Message, on eventLoop: EventLoop) -> EventLoopFuture<Message> {
        guard let question = message.questions.first else {
            return eventLoop.makeSucceededFuture(DNSRouter.createEmptyResponse(from: message))
        }

        let domain = question.labels.string
        let type = question.type

        print("DNS query: \(domain) [\(type)]")

        switch type {
        case .a:
            return forwardToLocalFuture(message, domain, question, on: eventLoop)
        default:
            return forwardToUpstreamFuture(message, domain: domain, type: type, on: eventLoop)
        }
    }

    private func forwardToLocalFuture(_ message: Message, _ domain: String, _: QuestionSection, on eventLoop: EventLoop) -> EventLoopFuture<Message> {
        let promise = eventLoop.makePromise(of: Message.self)
        Task {
            let fakeIP = await ipPool.assign(domain: domain)
            guard let fakeIP else {
                promise.succeed(DNSRouter.createEmptyResponse(from: message))
                return
            }
            guard let ipVal = fakeIP.uint32Value, let question = message.questions.first else {
                promise.succeed(DNSRouter.createEmptyResponse(from: message))
                return
            }
            #if DEBUG
                print("[DNSRouter] assigning fake A \(domain) -> \(fakeIP) (hostOrder=\(ipVal))")
            #endif
            let resourceRecord = ResourceRecord(domainName: question.labels, dataType: question.type.rawValue, dataClass: question.questionClass.rawValue, ttl: UInt32(ttl), resource: ARecord(address: ipVal))
            let answer = Record.a(resourceRecord)
            promise.succeed(DNSRouter.createResponse(from: message, with: [answer]))
        }
        return promise.futureResult
    }

    private func forwardToUpstreamFuture(_ message: Message, domain: String, type: DNSResourceType, on eventLoop: EventLoop) -> EventLoopFuture<Message> {
        guard let upstream = upstream else {
            print("No upstream resolver for: \(domain) [\(type)]")
            return eventLoop.makeSucceededFuture(DNSRouter.createEmptyResponse(from: message))
        }
        return upstream.resolveMessage(forHost: domain, type: type, on: eventLoop).map { upstreamMessage in
            DNSRouter.createResponse(from: message, with: upstreamMessage.answers, upstreamOptionsRaw: upstreamMessage.header.options.rawValue)
        }
    }

    public func getFakeIP(for domain: String) async -> IPAddress {
        return await ipPool.assign(domain: domain) ?? IPv4Address("0.0.0.0")!
    }

    public func reverseLookFakeIP(for ip: IPv4Address) async -> String? {
        return await ipPool.reverseLookup(ip)
    }

    public func clearFakeIPPool() async {
        await ipPool.clear()
        print("Fake IP pool cleared")
    }

    /// Create a response message.
    /// - Parameters:
    ///   - message: original incoming message (used for id/questions)
    ///   - answers: answers to include
    ///   - upstreamOptionsRaw: optional raw options from an upstream response; if provided, the RCODE bits (low 4 bits)
    ///     will be copied into the response. If nil, RCODE will be 0 (success).
    private static func createResponse(from message: Message, with answers: [Record], upstreamOptionsRaw: UInt16? = nil) -> Message {
        var responseOpt = message.header.options
        responseOpt.insert(.answer)
        responseOpt.insert(.recursionAvailable)

        // RCODE is the low 4 bits. If upstream provided options, inherit their RCODE bits.
        let rcodeMask: UInt16 = 0x000F
        let upstreamBits: UInt16 = upstreamOptionsRaw ?? 0
        responseOpt.rawValue = (responseOpt.rawValue & ~rcodeMask) | (upstreamBits & rcodeMask)

        let responseHeader = DNSMessageHeader(id: message.header.id, options: responseOpt, questionCount: message.header.questionCount, answerCount: UInt16(answers.count), authorityCount: 0, additionalRecordCount: 0)

        return Message(header: responseHeader, questions: message.questions, answers: answers, authorities: [], additionalData: [])
    }

    private static func createEmptyResponse(from message: Message) -> Message {
        // Pool exhausted or assignment failed: return SERVFAIL (RCODE=2)
        let servfailRCODE: UInt16 = 2
        return createResponse(from: message, with: [], upstreamOptionsRaw: servfailRCODE)
    }
}
