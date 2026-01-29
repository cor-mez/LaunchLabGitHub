//
//  TelemetryRingBuffer.swift
//  LaunchLab
//
//  Fixed-capacity telemetry ring buffer.
//
//  ROLE (STRICT):
//  - Hot-path safe for 120–240 FPS capture & RS observability
//  - No allocations on write
//  - No String formatting
//  - No logging / printing
//  - Pause-aware for controlled capture → dump workflows
//
//  NOTE:
//  - Uses an unfair lock (NOT lock-free)
//  - Acceptable for Phase-2 observability
//  - Chronology reconstructed offline via timestamps
//

import Foundation
import os.lock
import QuartzCore

// -----------------------------------------------------------------------------
// MARK: - Telemetry Event
// -----------------------------------------------------------------------------

struct TelemetryEvent {

    /// Monotonic timestamp (CACurrentMediaTime)
    let timestamp: Double

    /// Logical subsystem
    let phase: LogPhase

    /// Semantic event code
    ///
    /// RECOMMENDED ENCODING (Phase-2):
    ///   [ category | outcome | refusal_reason ]
    ///
    /// Example (RS observability):
    ///   0x40 = RS category
    ///   0x01 = refused
    ///   0x0001 = insufficientRowSupport
    ///
    ///   code = 0x4101
    ///
    let code: UInt16

    /// Scalar payload A (context-specific)
    let valueA: Float

    /// Scalar payload B (context-specific)
    let valueB: Float
}

// -----------------------------------------------------------------------------
// MARK: - Ring Buffer
// -----------------------------------------------------------------------------

final class TelemetryRingBuffer {

    static let shared = TelemetryRingBuffer(capacity: 4096)

    // -------------------------------------------------------------------------
    // MARK: - Storage
    // -------------------------------------------------------------------------

    private let capacity: Int
    private var buffer: [TelemetryEvent]
    private var writeIndex: Int = 0

    /// Unfair lock — short critical section, acceptable contention
    private let lock = OSAllocatedUnfairLock()

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

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

    // -------------------------------------------------------------------------
    // MARK: - Hot Path Write (Pause-Aware)
    // -------------------------------------------------------------------------

    @inline(__always)
    func push(
        phase: LogPhase,
        code: UInt16,
        valueA: Float = 0,
        valueB: Float = 0
    ) {
        // Hard gate — zero cost when paused
        guard !TelemetryControl.isPaused else { return }

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

    // -------------------------------------------------------------------------
    // MARK: - Snapshot (NON-HOT PATH ONLY)
    // -------------------------------------------------------------------------

    /// Returns entire ring buffer contents.
    ///
    /// NOTE:
    /// - Ordering is not guaranteed
    /// - Offline tools must sort by timestamp
    /// - writeIndex is intentionally not exposed in Phase-2
    ///
    func snapshot() -> [TelemetryEvent] {
        lock.withLock { buffer }
    }

    /// Returns buffer contents sorted by timestamp (NON-HOT PATH ONLY)
    func snapshotSorted() -> [TelemetryEvent] {
        lock.withLock {
            buffer
                .filter { $0.timestamp > 0 }
                .sorted { $0.timestamp < $1.timestamp }
        }
    }

    /// Reset the buffer to initial state (NON-HOT PATH ONLY)
    func reset() {
        lock.withLock {
            for i in 0..<capacity {
                buffer[i] = TelemetryEvent(
                    timestamp: 0,
                    phase: .detection,
                    code: 0,
                    valueA: 0,
                    valueB: 0
                )
            }
            writeIndex = 0
        }
    }

    /// Expose capacity for offline tooling sanity checks (NON-HOT PATH ONLY)
    var maxCapacity: Int {
        capacity
    }
}
