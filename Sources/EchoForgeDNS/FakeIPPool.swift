//
//  FakeIPPool.swift
//  EchoForgeDNS
//
//  Created by MagicianQuinn on 2025/12/11.
//
/// NOTE:
/// Fake IPs are NOT released in current phase.
/// LRU eviction will be implemented together with SOCKS5 / UDP NAT,
/// where "usage" semantics are well-defined.

import ForgeBase
import Foundation
import Network
import NIO

/// Fake IPv4 pool for DNS interception.
/// Convention:
/// - All UInt32 values are NETWORK BYTE ORDER (BE)
/// - Public API only exposes IPv4Address
public final class FakeIPPool {
    private let eventLoop: EventLoop

    /// Network base address (UInt32BE)
    private let baseBE: UInt32
    private let prefixLength: Int

    /// Total usable host count (excluding network / broadcast)
    private let capacity: UInt32

    /// Current offset [1 .. capacity]
    private var offset: UInt32 = 1

    private var ipToDomain: [IPv4Address: String] = [:]
    private var domainToIp: [String: IPv4Address] = [:]

    public init(
        cidr: String = "198.18.0.0/16",
        on eventLoop: EventLoop
    ) {
        self.eventLoop = eventLoop

        let parsed = FBIPv4Parse.parseCIDR(cidr)

        let fallback: UInt32 = 0xC612_0000 // "198.18.0.0"
        let networkBE = parsed?.networkBE ?? fallback

        let prefixLength = parsed?.prefixLength ?? 16
        let hostBits = UInt32(32 - prefixLength)

        baseBE = networkBE
        self.prefixLength = prefixLength

        let totalHosts = UInt64(1) << UInt64(hostBits)
        let usable =
            totalHosts > 3 ? totalHosts - 3 : 0 // exclude network/broadcast

        capacity = UInt32(min(usable, UInt64(UInt32.max)))
        offset = 2
    }

    // MARK: - Allocation

    /// Assign (or return existing) fake IP for domain.
    /// Must be called on pool eventLoop.
    public func assign(domain: String) -> IPv4Address? {
        eventLoop.assertInEventLoop()

        let now = NIODeadline.now()

        if let ip = domainToIp[domain] {
            return ip
        }

        guard capacity > 1 else { return nil }

        for _ in 0 ..< Int(capacity) {
            let candidateBE = baseBE &+ offset
            offset = (offset % capacity) + 1

            guard let ip = FBIPv4(beValue: candidateBE).asNetworkIPv4Address, ipToDomain[ip] == nil else {
                continue
            }

            domainToIp[domain] = ip
            ipToDomain[ip] = domain
            return ip
        }

        // pool exhausted
        return nil
    }

    // MARK: - Reverse lookup

    /// Reverse lookup fake IP → domain.
    /// Must be called on pool eventLoop.
    public func reverseLookup(_ ip: IPv4Address) -> String? {
        eventLoop.assertInEventLoop()
        return ipToDomain[ip]
    }

    public func isFakeIP(_ ip: IPv4Address) -> Bool {
        eventLoop.assertInEventLoop()
        return FBIPv4CIDR.contains(address: ip, networkBE: baseBE, prefixLength: prefixLength)
    }

    // MARK: - debug-only

    #if DEBUG
        /// Clear all mappings.
        /// Must be called on pool eventLoop.
        public func clear() {
            eventLoop.assertInEventLoop()

            ipToDomain.removeAll()
            domainToIp.removeAll()
            offset = 2
        }
    #endif
}
