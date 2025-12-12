//
//  DNSServerUDP.swift
//  EchoForgeDNS
//
//  Created by MagicianQuinn on 2025/12/10.
//

import DNSClient
import Foundation
import NIO

public final class DNSServerUDP {
    private let group: EventLoopGroup
    private let router: DNSRouter
    private let listenPort: UInt16 = 53
    private var udpChannel: Channel?

    public init(group: EventLoopGroup, upstreamHost: String = "8.8.8.8", upstreamPort: UInt16 = 53) throws {
        self.group = group
        // Create DNSClientAdapter (EventLoop-driven) and pass it to router.
        let upstreamAdapter = try? DNSClientAdapter(group: group, upstreamHost: upstreamHost, upstreamPort: upstreamPort)
        router = DNSRouter(upstream: upstreamAdapter, ipPool: FakeIPPool())
    }

    public func start() throws {
        let bootstrap = DatagramBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { [weak self] channel in
                guard let weakSelf = self else {
                    return channel.eventLoop.makeFailedFuture(EventLoopError.shutdown)
                }

                let handler = DNSDatagramHandler(router: weakSelf.router)
                return channel.pipeline.addHandlers(handler)
            }
        udpChannel = try bootstrap.bind(host: "0.0.0.0", port: Int(listenPort)).wait()
        print("UDP DNS server started on port \(listenPort)")
    }

    public func stop() throws {
        do {
            try udpChannel?.close().wait()
            try group.syncShutdownGracefully()
            print("DNS server stopped")
        } catch {
            print("Error stopping server: \(error)")
        }
    }
}
