//
//  Signpost.swift
//  LaunchLab
//
//  Zero-overhead timeline instrumentation.
//  Viewable in Instruments.
//

import os.signpost

enum Signpost {

    static let log = OSLog(
        subsystem: "com.launchlab.engine",
        category: "rs"
    )

    @inline(__always)
    static func begin(_ name: StaticString) {
        os_signpost(.begin, log: log, name: name)
    }

    @inline(__always)
    static func end(_ name: StaticString) {
        os_signpost(.end, log: log, name: name)
    }

    @inline(__always)
    static func event(_ name: StaticString) {
        os_signpost(.event, log: log, name: name)
    }
}
