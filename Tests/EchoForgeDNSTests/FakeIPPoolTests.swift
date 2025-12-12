import DNSClient
@testable import EchoForgeDNS
import Testing

@Suite("FakeIPPool")
struct FakeIPPoolTests {
    @Test("Duplicate allocation returns same IP; reverse & clear")
    func allocationDuplicateReverseClear() async throws {
        let ipPool = FakeIPPool()
        let a = await ipPool.assign(domain: "dup.com")
        #expect(a != nil)
        let b = await ipPool.assign(domain: "dup.com")
        #expect(b != nil)
        #expect(a == b)
        if let a = a {
            #expect(await ipPool.reverseLookup(a) == "dup.com")
        }
        await ipPool.clear()
        if let a = a {
            #expect(await ipPool.reverseLookup(a) == nil)
        }
    }

    @Test("Multiple allocations use different IPs")
    func multipleAllocations() async throws {
        let ipPool = FakeIPPool()
        let ip1 = await ipPool.assign(domain: "domain1.com")
        let ip2 = await ipPool.assign(domain: "domain2.com")
        let ip3 = await ipPool.assign(domain: "domain3.com")
        
        #expect(ip1 != nil)
        #expect(ip2 != nil)
        #expect(ip3 != nil)
        #expect(ip1 != ip2)
        #expect(ip2 != ip3)
        #expect(ip1 != ip3)
    }

    @Test("Small CIDR pool exhaustion")
    func smallCIDRPoolExhaustion() async throws {
        // /30 CIDR has 4 total IPs, excluding network and broadcast addresses leaves 2 usable IPs
        let ipPool = FakeIPPool(cidr: "192.168.1.0/30")
        let ip1 = await ipPool.assign(domain: "domain1.com")
        let ip2 = await ipPool.assign(domain: "domain2.com")
        let ip3 = await ipPool.assign(domain: "domain3.com")
        
        #expect(ip1 != nil)
        #expect(ip2 != nil)
        #expect(ip3 == nil) // Pool exhausted
    }

    @Test("Clear resets pool state")
    func clearResetsPoolState() async throws {
        let ipPool = FakeIPPool(cidr: "192.168.1.0/30")
        _ = await ipPool.assign(domain: "domain1.com")
        _ = await ipPool.assign(domain: "domain2.com")
        
        // Pool should be exhausted
        let exhausted = await ipPool.assign(domain: "domain3.com")
        #expect(exhausted == nil)
        
        // After clear, should be able to allocate again
        await ipPool.clear()
        let afterClear = await ipPool.assign(domain: "domain4.com")
        #expect(afterClear != nil)
    }

    @Test("Release returns IP to free list")
    func releaseReturnsIPToFreeList() async throws {
        let ipPool = FakeIPPool(cidr: "192.168.1.0/30")
        let ip1 = await ipPool.assign(domain: "domain1.com")
        let ip2 = await ipPool.assign(domain: "domain2.com")
        
        #expect(ip1 != nil)
        #expect(ip2 != nil)
        
        // Pool should be exhausted
        let exhausted = await ipPool.assign(domain: "domain3.com")
        #expect(exhausted == nil)
        
        // Release one IP
        await ipPool.release(domain: "domain1.com")
        
        // Should be able to allocate again
        let ip3 = await ipPool.assign(domain: "domain3.com")
        #expect(ip3 != nil)
        
        // Verify domain1.com is no longer mapped
        if let ip1 = ip1 {
            #expect(await ipPool.reverseLookup(ip1) == nil)
        }
    }

    @Test("Release non-existent domain is safe")
    func releaseNonExistentDomain() async throws {
        let ipPool = FakeIPPool()
        // Should not crash or cause issues
        await ipPool.release(domain: "nonexistent.com")
        
        // Pool should still work normally
        let ip = await ipPool.assign(domain: "test.com")
        #expect(ip != nil)
    }
}
