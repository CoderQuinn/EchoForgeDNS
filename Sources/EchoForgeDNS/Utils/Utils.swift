//
//  Utils.swift
//  EchoForgeDNS
//
//  Created by MagicianQuinn on 2025/12/10.
//

import Foundation
import Network

enum IPUtils {
    /// Converts a dotted-decimal string to a UInt32 (host byte order).
    static func ipv4ToUInt32(_ ipString: String) -> UInt32? {
        let components = ipString.split(separator: ".")
        guard components.count == 4 else { return nil }

        var result: UInt32 = 0
        for component in components {
            guard let number = UInt32(component),
                  number <= 255 else { return nil }
            result = (result << 8) | number
        }

        return result
    }

    /// Converts a UInt32 (host byte order) to a dotted-decimal string.
    static func string(fromUInt32HostOrder value: UInt32) -> String {
        let octet1 = UInt8((value >> 24) & 0xFF)
        let octet2 = UInt8((value >> 16) & 0xFF)
        let octet3 = UInt8((value >> 8) & 0xFF)
        let octet4 = UInt8(value & 0xFF)

        return "\(octet1).\(octet2).\(octet3).\(octet4)"
    }

    /// Converts a UInt32 (host byte order) to an IPv4Address.
    static func address(fromUInt32HostOrder value: UInt32) -> IPv4Address? {
        let ipString = string(fromUInt32HostOrder: value)
        return IPv4Address(ipString)
    }

    /// Converts a UInt32 (network byte order) to an IPv4Address.
    static func address(fromUInt32NetworkOrder value: UInt32) -> IPv4Address? {
        let hostOrderValue = UInt32(bigEndian: value)
        return address(fromUInt32HostOrder: hostOrderValue)
    }

    /// Parses a CIDR like "198.18.0.0/16" and returns the network base (host order)
    /// and the mask bit width (e.g. 16).
    static func parseCIDR(_ cidr: String) -> (base: UInt32, maskBits: Int)? {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2,
              let ipString = parts.first,
              let maskBits = Int(parts[1]),
              maskBits >= 0, maskBits <= 32,
              let baseIP = ipv4ToUInt32(String(ipString))
        else {
            return nil
        }

        let maskBitsClamped = maskBits
        let mask: UInt32 = maskBitsClamped == 0 ? 0 : ~((1 << (32 - maskBitsClamped)) - 1)
        let network = baseIP & mask

        return (network, maskBitsClamped)
    }
}

extension IPv4Address {
    /// Gets the UInt32 representation of this address (host byte order).
    var uint32Value: UInt32? {
        return IPUtils.ipv4ToUInt32(String(describing: self))
    }

    /// Gets the UInt32 representation of this address (network byte order).
    var uint32NetworkOrderValue: UInt32? {
        return uint32Value?.bigEndian
    }
}
