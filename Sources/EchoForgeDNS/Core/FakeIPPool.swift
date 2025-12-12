//
//  FakeIPPool.swift
//  EchoForgeDNS
//
//  Created by MagicianQuinn on 2025/12/11.
//

import Foundation
import Network
import NIOConcurrencyHelpers
import NIOTransportServices

// support IPv4, TODO: implement IPv6
public final class FakeIPPool: Sendable {
    private let base: UInt32
    private let capacity: UInt32
    private let lock = NIOLock()
    private var offset: UInt32 = 0

    private var ipToDomain: [IPv4Address: String] = [:]
    private var domainToIp: [String: IPv4Address] = [:]

    public init(cidr: String = "198.18.0.0/16") {
        let start: UInt32
        let hostBits: UInt32
        if let parsed = IPUtils.parseCIDR(cidr) {
            start = parsed.base
            let maskBits = parsed.maskBits
            hostBits = UInt32(32 - maskBits)
        } else {
            start = IPUtils.ipv4ToUInt32("198.18.0.0") ?? 0
            hostBits = 32 - 16
        }

        base = start
        let totalHosts = UInt64(1) << UInt64(hostBits)
        let hostsMinusTwo = totalHosts > 2 ? totalHosts - 2 : 0
        capacity = UInt32(min(hostsMinusTwo, UInt64(UInt32.max)))
        offset = 1
    }

    public func assign(domain: String) -> IPv4Address? {
        lock.withLock {
            if let existing = domainToIp[domain] {
                return existing
            }

            // A temp soulution: Try to find an unassigned IP within capacity. If pool is exhausted, return nil.
            // We'll probe up to `capacity` candidates starting from `offset`.
            // TODO: use LRU
            guard capacity > 1 else { return nil }

            for _ in 0 ..< Int(capacity) {
                let candidate = base + offset
                // advance offset within 1..capacity (skip 0 to avoid network address)
                offset = ((offset % capacity) + 1)
                if let ip = IPv4Address(IPUtils.string(fromUInt32HostOrder: candidate)), ipToDomain[ip] == nil {
                    domainToIp[domain] = ip
                    ipToDomain[ip] = domain
                    return ip
                }
            }

            // No free IP found
            return nil
        }
    }

    public func reverseLookup(_ ip: IPv4Address) -> String? {
        lock.withLock {
            ipToDomain[ip]
        }
    }

    public func clear() {
        lock.withLock {
            ipToDomain.removeAll()
            domainToIp.removeAll()
            offset = ((offset % capacity) + 1)
        }
    }
}
