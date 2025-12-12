import DNSClient
@testable import EchoForgeDNS
import Testing

@Suite("FakeIPPool")
struct FakeIPPoolTests {
    @Test("Duplicate allocation returns same IP; reverse & clear")
    func allocationDuplicateReverseClear() throws {
        let ipPool = FakeIPPool()
        let a = ipPool.assign(domain: "dup.com")
        #expect(a != nil)
        let b = ipPool.assign(domain: "dup.com")
        #expect(b != nil)
        #expect(a == b)
        if let a = a {
            #expect(ipPool.reverseLookup(a) == "dup.com")
        }
        ipPool.clear()
        if let a = a {
            #expect(ipPool.reverseLookup(a) == nil)
        }
    }
}
