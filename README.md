
# EchoForgeDNS

![Swift](https://img.shields.io/badge/Swift-6.1-orange?logo=swift)
![Platform](https://img.shields.io/badge/Platform-iOS%2013%2B%20%7C%20macOS%2011%2B-blue)

**EchoForgeDNS** is a lightweight, embeddable DNS component written in Swift.
It is designed for use in larger networking tools, such as intercepting and rewriting A-records for selected domains while leaving other DNS traffic to normal resolvers.


## Features

- **UDP DNS** handling (port 53)
- **Fake-IP pool** using the RFC 6890 reserved range `198.18.0.0/16`
- **Pluggable upstream resolver** (`DNSResolverProtocol`) for easy testing and adaptation
- **SwiftNIO** for non-blocking performance


## Installation

Add **EchoForgeDNS** to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/CoderQuinn/EchoForgeDNS.git", from: "0.2.0")
]
```

Then add `EchoForgeDNS` to your target dependencies:

```swift
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "EchoForgeDNS", package: "EchoForgeDNS")
        ]
    ),
]
```


## Usage Example

```swift
import EchoForgeDNS

// Example: Initialize DNS service (see documentation for details)
let dnsService = DNSService(/* configuration */)
dnsService.start()
```

## Design Notes

- Tests avoid constructing internal types from the `DNSClient` dependency; instead, they build raw DNS packets and parse them with `DNSDecoder` to produce `Message` instances. This keeps tests resilient to access-control changes in the dependency.
- The Fake-IP pool intentionally uses `198.18.0.0/16` (RFC 6890 reserved block) to avoid colliding with public IPv4 space.


## Roadmap / TODO

- [ ] TCP, DoT (DNS over TLS), DoH (DNS over HTTPS)
- [ ] IPv6 support for fake addresses
- [ ] LRU recycling algorithm for Fake-IP reuse
- [x] Built-in caching with TTL awareness


## Contributing

Patches, tests, and documentation improvements are welcome! Please open a PR against this repository.

## Credits

- SwiftNIO: https://github.com/apple/swift-nio
- DNSClient: https://github.com/orlandos-nl/DNSClient

## License
Apache 2.0 License.
