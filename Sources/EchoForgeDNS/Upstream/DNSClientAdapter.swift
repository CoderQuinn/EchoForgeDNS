//
//  DNSClientAdapter.swift
//  EchoForgeDNS
//
//  Created by MagicianQuinn on 2025/12/11.
//

import DNSClient
import Foundation
import NIO

public final class DNSClientAdapter: DNSResolverProtocol {
    private let group: EventLoopGroup
    private var clientFuture: EventLoopFuture<DNSClient>?

    public init(group: EventLoopGroup, upstreamHost: String = "8.8.8.8", upstreamPort: UInt16 = 53) throws {
        self.group = group
        let config = try SocketAddress(ipAddress: upstreamHost, port: Int(upstreamPort))
        // Start connect; store the future
        clientFuture = DNSClient.connect(on: group, config: [config])
    }

    public func resolveMessage(forHost host: String, type: DNSResourceType, on eventLoop: EventLoop) -> EventLoopFuture<Message> {
        guard let clientFuture = clientFuture else {
            return eventLoop.makeFailedFuture(NSError(domain: "DNSClientAdapter", code: 1, userInfo: [NSLocalizedDescriptionKey: "DNS client not initialized"]))
        }

        return clientFuture.flatMap { client in
            client.sendQuery(forHost: host, type: type)
        }
    }
}
