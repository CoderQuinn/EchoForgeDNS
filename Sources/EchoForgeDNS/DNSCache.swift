//
//  DNSCache.swift
//  NetForge
//
//  Created by MagicianQuinn on 2025/12/28.
//

import DNSClient
import Foundation
import Network
import NIO

struct DNSCacheKey: Hashable {
    let domain: String
    let type: DNSResourceType
}

struct DNSCacheEntry {
    let key: DNSCacheKey
    let answers: [Record]
    let expireAt: NIODeadline
    var realIPs: [IPv4Address]?
}

public final class DNSCache {
    private let eventLoop: EventLoop
    private var table: [DNSCacheKey: DNSCacheEntry] = [:]

    init(eventLoop: EventLoop) {
        self.eventLoop = eventLoop
    }

    func lookup(_ key: DNSCacheKey) -> DNSCacheEntry? {
        eventLoop.assertInEventLoop()

        guard let entry = table[key] else {
            return nil
        }

        if entry.expireAt <= .now() {
            table.removeValue(forKey: key)
            return nil
        }
        return entry
    }

    func insert(_ entry: DNSCacheEntry) {
        eventLoop.assertInEventLoop()

        table[entry.key] = entry
    }

    func sweepExpired(_ now: NIODeadline = .now(), _ handler: ([DNSCacheEntry]) -> Void) {
        eventLoop.assertInEventLoop()

        var removed: [DNSCacheEntry] = []
        for (key, entry) in table {
            if entry.expireAt <= now {
                table.removeValue(forKey: key)
                removed.append(entry)
            }
        }

        handler(removed)
    }
}
