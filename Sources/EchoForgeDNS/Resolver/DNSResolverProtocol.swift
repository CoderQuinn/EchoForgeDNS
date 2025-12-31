//
//  DNSResolverProtocol.swift
//  EchoForgeDNS
//
//  Created by MagicianQuinn on 2025/12/11.
//

import DNSClient
import NIO

public protocol DNSResolverProtocol {
    func resolveMessage(forHost host: String, type: DNSResourceType, on eventLoop: EventLoop) -> EventLoopFuture<Message>
}
