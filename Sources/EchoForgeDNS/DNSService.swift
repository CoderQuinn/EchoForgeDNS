//
//  DNSService.swift
//  NetForge
//
//  Created by MagicianQuinn on 2025/12/27.
//

import DNSClient
import ForgeBase
import Foundation
import Network
import NIO

public protocol DNSResolverProtocol {
    func resolveMessage(
        _ host: String,
        _ type: DNSResourceType,
        _ eventLoop: EventLoop
    ) -> EventLoopFuture<Message>
}

public struct DialDecision {
    public let dialIP: IPv4Address?
    public let dialHost: String?
    public let fromFakeIP: Bool
}

public final class DNSService {
    public let eventLoop: EventLoop

    private let cache: DNSCache
    private let ipPool: FakeIPPool
    private let upstreamFactory: (() throws -> DNSResolverProtocol)?
    private var upstream: DNSResolverProtocol?
    private let ttl: Int // seconds

    private var sweepTask: RepeatedTask?

    init(
        eventLoop: EventLoop,
        ttl: Int,
        upstreamFactory: (() throws -> DNSResolverProtocol)?
    ) {
        self.eventLoop = eventLoop
        self.upstreamFactory = upstreamFactory
        self.ttl = ttl

        cache = DNSCache(eventLoop: eventLoop)
        ipPool = FakeIPPool(on: eventLoop)
    }

    // MARK: - Upstream

    private func getUpstream() -> DNSResolverProtocol? {
        eventLoop.assertInEventLoop()

        if let upstream {
            return upstream
        }

        guard let factory = upstreamFactory else {
            EFLog.warn("DNSService.getUpstream: no factory")
            return nil
        }

        do {
            let created = try factory()
            upstream = created
            EFLog.info("DNSService upstream created")
            return created
        } catch {
            EFLog.error("DNSService upstream create failed: \(error)")
            return nil
        }
    }

    // MARK: - Public API (any loop)

    public func handleDNS(
        _ message: Message,
        _ callerLoop: EventLoop
    ) -> EventLoopFuture<Message> {
        EFLog.debug("DNS.handle enter qid=\(message.header.id) qcount=\(message.questions.count)")

        return eventLoop.flatSubmit { [weak self] in
            guard let self else {
                return callerLoop.makeSucceededFuture(
                    Self.createServFail(from: message)
                )
            }

            self.eventLoop.assertInEventLoop()
            return self.handleDNSInternal(message)
        }
        .hop(to: callerLoop)
    }

    public func reverseLookup(
        _ ip: IPv4Address,
        _ callerLoop: EventLoop
    ) -> EventLoopFuture<String?> {
        return eventLoop.flatSubmit { [weak self] in
            guard let self else {
                return callerLoop.makeSucceededFuture(nil)
            }

            self.eventLoop.assertInEventLoop()
            let domain = self.ipPool.reverseLookup(ip)

            EFLog.debug("DNS.reverseLookup ip=\(ip) domain=\(domain ?? "nil")")

            return self.eventLoop.makeSucceededFuture(domain)
        }
        .hop(to: callerLoop)
    }

    public func cachedRealIPs(
        domain: String,
        _ callerLoop: EventLoop
    ) -> EventLoopFuture<[IPv4Address]?> {
        return eventLoop.flatSubmit { [weak self] in
            guard let self else {
                return callerLoop.makeSucceededFuture(nil)
            }

            self.eventLoop.assertInEventLoop()

            let key = DNSCacheKey(domain: domain, type: .a)
            let ips = self.cache.lookup(key)?.realIPs

            EFLog.debug("DNS.cachedRealIPs domain=\(domain) hit=\(ips != nil)")

            return self.eventLoop.makeSucceededFuture(ips)
        }
        .hop(to: callerLoop)
    }

    public func resolveDialDecision(
        _ dstIP: IPv4Address,
        _ callerLoop: EventLoop
    ) -> EventLoopFuture<DialDecision> {
        return eventLoop.flatSubmit { [weak self] in
            let direct = DialDecision(
                dialIP: dstIP,
                dialHost: nil,
                fromFakeIP: false
            )

            guard let self else {
                return callerLoop.makeSucceededFuture(direct)
            }

            self.eventLoop.assertInEventLoop()

            guard self.ipPool.isFakeIP(dstIP) else {
                return self.eventLoop.makeSucceededFuture(direct)
            }

            guard let domain = self.ipPool.reverseLookup(dstIP) else {
                EFLog.warn("DialDecision fakeIP without mapping ip=\(dstIP)")
                return self.eventLoop.makeSucceededFuture(
                    DialDecision(dialIP: nil, dialHost: nil, fromFakeIP: true)
                )
            }

            let key = DNSCacheKey(domain: domain, type: .a)

            if let real = self.cache.lookup(key)?.realIPs?.first {
                EFLog.debug("DialDecision resolved from cache domain=\(domain) ip=\(real)")
                return self.eventLoop.makeSucceededFuture(
                    DialDecision(dialIP: real, dialHost: nil, fromFakeIP: true)
                )
            }

            EFLog.debug("DialDecision need prefetch domain=\(domain)")

            self.prefetchAIfNeeded(domain: domain)

            return self.eventLoop.makeSucceededFuture(
                DialDecision(dialIP: nil, dialHost: domain, fromFakeIP: true)
            )
        }
        .hop(to: callerLoop)
    }

    // MARK: - Prefetch

    public func prefetchAIfNeeded(domain: String) {
        eventLoop.execute { [weak self] in
            guard let self else { return }
            self.eventLoop.assertInEventLoop()

            let key = DNSCacheKey(domain: domain, type: .a)

            if self.cache.lookup(key)?.realIPs != nil {
                EFLog.debug("DNS.prefetch skip (have realIP) domain=\(domain)")
                return
            }

            guard let upstream = self.getUpstream() else {
                EFLog.warn("DNS.prefetch no upstream domain=\(domain)")
                return
            }

            EFLog.debug("DNS.prefetch A start domain=\(domain)")

            upstream
                .resolveMessage(domain, .a, self.eventLoop)
                .whenSuccess { [weak self] resp in
                    self?.handleUpstreamAResult(
                        domain: domain,
                        upstreamMsg: resp
                    )
                }
        }
    }

    // MARK: - Internal (dnsLoop)

    private func handleDNSInternal(
        _ message: Message
    ) -> EventLoopFuture<Message> {
        eventLoop.assertInEventLoop()

        guard let question = message.questions.first else {
            EFLog.warn("DNSService empty question")
            return eventLoop.makeSucceededFuture(
                Self.createServFail(from: message)
            )
        }

        let domain = question.labels.string
        let type = question.type

        EFLog.debug("DNS.query domain=\(domain) type=\(type)")

        switch type {
        case .a:
            return handleLocal(message, domain: domain, question: question)

        default:
            EFLog.debug("DNS.forward upstream domain=\(domain) type=\(type)")
            return handleUpstream(message, domain: domain, type: type)
        }
    }

    private func handleLocal(
        _ message: Message,
        domain: String,
        question: QuestionSection
    ) -> EventLoopFuture<Message> {
        eventLoop.assertInEventLoop()

        let key = DNSCacheKey(domain: domain, type: .a)

        if let cached = cache.lookup(key) {
            EFLog.debug("DNS.cache HIT domain=\(domain) answers=\(cached.answers.count) realIPs=\(cached.realIPs != nil)")
            return eventLoop.makeSucceededFuture(
                Self.createResponse(from: message, with: cached.answers)
            )
        }

        EFLog.debug("DNS.cache MISS domain=\(domain)")

        guard let fakeIP = ipPool.assign(domain: domain) else {
            EFLog.error("FakeIPPool exhausted domain=\(domain)")
            return eventLoop.makeSucceededFuture(
                Self.createServFail(from: message)
            )
        }

        EFLog.info("DNS.fakeIP assign domain=\(domain) ip=\(fakeIP)")

        let rr = ResourceRecord(
            domainName: question.labels,
            dataType: question.type.rawValue,
            dataClass: question.questionClass.rawValue,
            ttl: UInt32(ttl),
            resource: ARecord(address: FBIPv4(fakeIP).beValue)
        )

        let answer = Record.a(rr)

        let entry = DNSCacheEntry(
            key: key,
            answers: [answer],
            expireAt: .now() + .seconds(Int64(ttl))
        )

        cache.insert(entry)

        EFLog.debug("DNS.cache INSERT domain=\(domain) ttl=\(ttl)")

        prefetchAIfNeeded(domain: domain)

        return eventLoop.makeSucceededFuture(
            Self.createResponse(from: message, with: [answer])
        )
    }

    private func handleUpstreamAResult(
        domain: String,
        upstreamMsg: Message
    ) {
        eventLoop.assertInEventLoop()

        let key = DNSCacheKey(domain: domain, type: .a)

        guard var entry = cache.lookup(key) else {
            EFLog.warn("Upstream A result but cache missing domain=\(domain)")
            return
        }

        let realIPs: [IPv4Address] = upstreamMsg.answers.compactMap {
            if case let .a(rr) = $0, let ip = FBIPv4(beValue: rr.resource.address).asNetworkIPv4Address {
                return ip
            }
            return nil
        }

        guard !realIPs.isEmpty else {
            EFLog.debug("Upstream A empty result domain=\(domain)")
            return
        }

        entry.realIPs = realIPs
        cache.insert(entry)

        EFLog.info("DNS.upstream resolved domain=\(domain) realIPs=\(realIPs)")
    }

    // MARK: - Sweep

    public func startSweep() {
        let interval = Int64(ttl / 2)

        sweepTask = eventLoop.scheduleRepeatedTask(
            initialDelay: .seconds(interval),
            delay: .seconds(interval)
        ) { [weak self] _ in
            guard let self = self else { return }

            self.cache.sweepExpired { arr in
                if arr.count > 0 {
                    EFLog.debug("DNS.cache sweep expired=\(arr.count)")
                }
            }
        }
    }

    public func stopSweep() {
        sweepTask?.cancel()
        sweepTask = nil
    }

    // MARK: - Upstream fallback

    private func handleUpstream(
        _ message: Message,
        domain: String,
        type: DNSResourceType
    ) -> EventLoopFuture<Message> {
        eventLoop.assertInEventLoop()

        guard let upstream = getUpstream() else {
            EFLog.error("DNS.upstream unavailable domain=\(domain)")
            return eventLoop.makeSucceededFuture(
                Self.createServFail(from: message)
            )
        }

        return upstream
            .resolveMessage(domain, type, eventLoop)
            .map { upstreamMessage in
                Self.createResponse(
                    from: message,
                    with: upstreamMessage.answers,
                    upstreamOptionsRaw: upstreamMessage.header.options.rawValue
                )
            }
            .flatMapError { error in
                EFLog.error("DNS.upstream error domain=\(domain) err=\(error)")
                return self.eventLoop.makeSucceededFuture(
                    Self.createServFail(from: message)
                )
            }
    }

    // MARK: - Response builders

    private static func createResponse(
        from message: Message,
        with answers: [Record],
        upstreamOptionsRaw: UInt16? = nil
    ) -> Message {
        var opt = message.header.options
        opt.insert(.answer)
        opt.insert(.recursionAvailable)

        let rcodeMask: UInt16 = 0x000F
        let upstreamBits: UInt16 = upstreamOptionsRaw ?? 0
        opt.rawValue = (opt.rawValue & ~rcodeMask) | (upstreamBits & rcodeMask)

        let header = DNSMessageHeader(
            id: message.header.id,
            options: opt,
            questionCount: message.header.questionCount,
            answerCount: UInt16(answers.count),
            authorityCount: 0,
            additionalRecordCount: 0
        )

        return Message(
            header: header,
            questions: message.questions,
            answers: answers,
            authorities: [],
            additionalData: []
        )
    }

    private static func createServFail(
        from message: Message
    ) -> Message {
        let servfailRCODE: UInt16 = 2
        return createResponse(
            from: message,
            with: [],
            upstreamOptionsRaw: servfailRCODE
        )
    }
}
