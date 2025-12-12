//
//  FakeIPPool.swift
//  EchoForgeDNS
//
//  Created by MagicianQuinn on 2025/12/11.
//

import Foundation
import Network
import NIOTransportServices

// support IPv4, TODO: implement IPv6
public actor FakeIPPool {
    private let base: UInt32
    private let capacity: UInt32
    
    private var ipToDomain: [IPv4Address: String] = [:]
    private var domainToIp: [String: IPv4Address] = [:]
    
    // Free list for O(1) allocation: tracks released IP offsets
    private var freeOffsets: [UInt32] = []
    // Track next unallocated offset for initial allocations
    private var nextOffset: UInt32 = 1

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
    }

    public func assign(domain: String) -> IPv4Address? {
        if let existing = domainToIp[domain] {
            return existing
        }

        // Try to allocate an IP, retrying up to a reasonable limit if IP creation fails
        let maxAttempts = 10
        for _ in 0..<maxAttempts {
            // O(1) allocation: try free list first, then allocate from nextOffset
            let offset: UInt32
            if let freedOffset = freeOffsets.popLast() {
                offset = freedOffset
            } else {
                // Check if we have capacity for new allocation
                guard nextOffset <= capacity else {
                    return nil
                }
                offset = nextOffset
                nextOffset += 1
            }
            
            let candidate = base + offset
            if let ip = IPv4Address(IPUtils.string(fromUInt32HostOrder: candidate)),
               ipToDomain[ip] == nil {
                domainToIp[domain] = ip
                ipToDomain[ip] = domain
                return ip
            }
            // If IP creation failed or IP already assigned, continue to try the next offset
        }
        
        // Failed to allocate after max attempts
        return nil
    }
    
    public func release(domain: String) {
        guard let ip = domainToIp[domain] else {
            return
        }
        
        domainToIp.removeValue(forKey: domain)
        ipToDomain.removeValue(forKey: ip)
        
        // Return offset to free list for reuse
        if let ipValue = ip.uint32Value {
            let offset = ipValue - base
            // Only add to free list if it's a valid offset that was actually allocated
            if offset >= 1 && offset < nextOffset && offset <= capacity {
                freeOffsets.append(offset)
            }
        }
    }

    public func reverseLookup(_ ip: IPv4Address) -> String? {
        return ipToDomain[ip]
    }

    public func clear() {
        ipToDomain.removeAll()
        domainToIp.removeAll()
        freeOffsets.removeAll()
        nextOffset = 1
    }
}
