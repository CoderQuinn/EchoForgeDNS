//
//  EFLog.swift
//  EchoForgeDNS
//
//  Created by MagicianQuinn on 2025/12/31.
//

import ForgeLogKit

public enum EFLog {
    @inline(__always)
    private static var log: FLLog {
        FLLog(
            subsystem: "com.EchoForgeDNS",
            category: "EchoForgeDNS"
        )
    }

    @inline(__always) public static func info(_ m: String) { log.info(m) }
    @inline(__always) public static func debug(_ m: String) { log.debug(m) }
    @inline(__always) public static func warn(_ m: String) { log.warn(m) }
    @inline(__always) public static func error(_ m: String) { log.error(m) }
}
