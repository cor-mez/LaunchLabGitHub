//
//  SignpostTrace.swift
//  LaunchLab
//
//  Timeline observability without FPS impact.
//

import os.signpost

enum SignpostTrace {

    private static let log = OSLog(
        subsystem: "com.launchlab.engine",
        category: "rs"
    )

    static let frame = OSSignpostID(log: log)

    @inline(__always)
    static func beginFrame() {
        os_signpost(.begin, log: log, name: "Frame", signpostID: frame)
    }

    @inline(__always)
    static func endFrame() {
        os_signpost(.end, log: log, name: "Frame", signpostID: frame)
    }

    @inline(__always)
    static func instant(_ name: StaticString) {
        os_signpost(.event, log: log, name: name)
    }
}
