# EchoForgeDNS

EchoForgeDNS is a lightweight, embeddable DNS component written in Swift.
This project is intended as a component inside larger networking tools — for example, to intercept and rewrite A-records for selected domains while leaving other DNS traffic to normal resolvers.

## Features

- UDP DNS handling (port 53)
- Fake-IP pool using the RFC 6890 reserved range `198.18.0.0/16`
- Pluggable upstream resolver (protocol `DNSResolverProtocol`) so you can inject mocks in tests or adapt to different DNS clients
- Built with SwiftNIO for non-blocking performance

## Installation

Add EchoForgeDNS to your Package.swift dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/<your-actual-org-or-username>/EchoForgeDNS.git", from: "0.1.0")
]
```

Then add the package target where you need it.

## Notes / Design choices

- Tests avoid constructing internal types from the `DNSClient` dependency; instead, they build raw DNS packets and parse them with `DNSDecoder` to produce `Message` instances. This keeps tests resilient to access-control changes in the dependency.
- The Fake-IP pool intentionally uses `198.18.0.0/16` (RFC 6890 reserved block) to avoid colliding with public IPv4 space.

## TODO

- [ ] TCP, DoT (DNS over TLS), DoH (DNS over HTTPS)
- [ ] IPv6 support for fake addresses
- [ ] LRU recycling algorithm for Fake-IP reuse
- [ ] Built-in caching with TTL awareness

## Contributing

Patches, tests, and documentation improvements are welcome — open a PR against this repository.

## Credits

- SwiftNIO: https://github.com/apple/swift-nio
- DNSClient: https://github.com/mikaoj/DNSClient

## License
Apache 2.0 License.