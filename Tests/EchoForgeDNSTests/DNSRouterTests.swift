import DNSClient
@testable import EchoForgeDNS
import NIO
import Testing

private func makeQueryMessage(domain: String, type: DNSResourceType = .a, id: UInt16 = 10) throws -> Message {
    let allocator = ByteBufferAllocator()
    var buf = allocator.buffer(capacity: 128)
    buf.writeInteger(id, endianness: .big)
    buf.writeInteger(UInt16(0), endianness: .big)
    buf.writeInteger(UInt16(1), endianness: .big)
    buf.writeInteger(UInt16(0), endianness: .big)
    buf.writeInteger(UInt16(0), endianness: .big)
    buf.writeInteger(UInt16(0), endianness: .big)

    for label in domain.split(separator: ".") {
        let bytes = Array(label.utf8)
        buf.writeInteger(UInt8(bytes.count))
        buf.writeBytes(bytes)
    }
    buf.writeInteger(UInt8(0))
    buf.writeInteger(type.rawValue, endianness: .big)
    buf.writeInteger(UInt16(1), endianness: .big)

    return try DNSDecoder.parse(buf)
}

private func makeResponseMessage(domain: String, ip: UInt32?, id: UInt16 = 11) throws -> Message {
    let allocator = ByteBufferAllocator()
    var buf = allocator.buffer(capacity: 256)
    buf.writeInteger(id, endianness: .big)
    buf.writeInteger(UInt16(0x8400), endianness: .big)
    buf.writeInteger(UInt16(1), endianness: .big)
    buf.writeInteger(ip != nil ? UInt16(1) : UInt16(0), endianness: .big)
    buf.writeInteger(UInt16(0), endianness: .big)
    buf.writeInteger(UInt16(0), endianness: .big)

    for label in domain.split(separator: ".") {
        let bytes = Array(label.utf8)
        buf.writeInteger(UInt8(bytes.count))
        buf.writeBytes(bytes)
    }
    buf.writeInteger(UInt8(0))
    buf.writeInteger(DNSResourceType.a.rawValue, endianness: .big)
    buf.writeInteger(UInt16(1), endianness: .big)

    if let ip = ip {
        buf.writeInteger(UInt16(0xC00C), endianness: .big)
        buf.writeInteger(UInt16(1), endianness: .big)
        buf.writeInteger(UInt16(1), endianness: .big)
        buf.writeInteger(UInt32(300), endianness: .big)
        buf.writeInteger(UInt16(4), endianness: .big)
        buf.writeInteger(ip, endianness: .big)
    }

    return try DNSDecoder.parse(buf)
}

@Suite("DNSRouter")
struct DNSRouterTests {
    final class MockDNSResolver: DNSResolverProtocol {
        var responses: [String: UInt32] = [:]

        func resolveMessage(forHost host: String, type _: DNSResourceType, on eventLoop: EventLoop) -> EventLoopFuture<Message> {
            do {
                let msg = try makeResponseMessage(domain: host, ip: responses[host], id: UInt16.random(in: 0 ... UInt16.max))
                return eventLoop.makeSucceededFuture(msg)
            } catch {
                return eventLoop.makeFailedFuture(error)
            }
        }
    }

    @Test("Local A resolution from pool")
    func localAResolution() async throws {
        let ipPool = FakeIPPool()
        let router = DNSRouter(upstream: nil, ipPool: ipPool)
        let eventLoop = EmbeddedEventLoop()

        let message = try makeQueryMessage(domain: "local.test")

        let response = try router.handleInboundFuture(message, on: eventLoop).wait()
        #expect(response.answers.count == 1)
        if case let .a(record)? = response.answers.first {
            let assigned = await ipPool.assign(domain: "local.test")
            #expect(assigned != nil)
            if let assigned = assigned {
                #expect(record.resource.address == assigned.uint32Value)
            }
        } else {
            Issue.record("Expected A record")
        }
    }

    @Test("Upstream resolution for non-A type")
    func upstreamResolution() throws {
        let mock = MockDNSResolver()
        mock.responses["upstream.test"] = IPUtils.ipv4ToUInt32("5.6.7.8")

        let router = DNSRouter(upstream: mock, ipPool: FakeIPPool())
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }
        let eventLoop = group.next()

        // Request a non-A type so the router will forward to upstream (A queries are handled locally)
        let message = try makeQueryMessage(domain: "upstream.test", type: .ns)

        let response = try router.handleInboundFuture(message, on: eventLoop).wait()
        #expect(response.answers.count == 1)
        if case let .a(record)? = response.answers.first {
            #expect(record.resource.stringAddress == "5.6.7.8")
        } else {
            Issue.record("Expected A record from upstream")
        }
    }
}
