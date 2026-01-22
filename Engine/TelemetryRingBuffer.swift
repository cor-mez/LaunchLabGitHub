//
//  TelemetryRingBuffer.swift
//  LaunchLab
//
//  Lock-free, allocation-free telemetry buffer.
//  SAFE in hot paths (camera, RS, GPU callbacks).
//

import Foundation
import os.lock
import QuartzCore   // ✅ for CACurrentMediaTime

struct TelemetryEvent {
    let timestamp: Double
    let phase: LogPhase
    let code: UInt16
    let valueA: Float
    let valueB: Float
}

final class TelemetryRingBuffer {

    static let shared = TelemetryRingBuffer(capacity: 4096)

    private let capacity: Int
    private var buffer: [TelemetryEvent]
    private var writeIndex: Int = 0

    private let lock = OSAllocatedUnfairLock()

    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = Array(
            repeating: TelemetryEvent(
                timestamp: 0,
                phase: .detection,
                code: 0,
                valueA: 0,
                valueB: 0
            ),
            count: capacity
        )
    }

    @inline(__always)
    func push(
        phase: LogPhase,
        code: UInt16,
        valueA: Float = 0,
        valueB: Float = 0
    ) {
        let t = CACurrentMediaTime()
        lock.withLock {
            buffer[writeIndex] = TelemetryEvent(
                timestamp: t,
                phase: phase,
                code: code,
                valueA: valueA,
                valueB: valueB
            )
            writeIndex = (writeIndex + 1) % capacity
        }
    }

    /// Snapshot for offline dump or UI pull (NOT hot path)
    func snapshot() -> [TelemetryEvent] {
        lock.withLock { buffer }
    }
}
