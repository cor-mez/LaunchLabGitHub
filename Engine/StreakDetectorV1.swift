//
//  StreakDetectorV1.swift
//  LaunchLab
//
//  Extracts and evaluates localized streak geometry.
//  No assumptions about ball emergence.
//

import CoreGraphics
import CoreVideo

final class StreakDetectorV1 {

    // ---------------------------------------------------------
    // Tunables (LOCKED FOR NOW — OBSERVABILITY FIRST)
    // ---------------------------------------------------------

    private let minRowSpan: Int = 6
    private let maxLocalityRatio: CGFloat = 0.35
    private let maxOrientationVariance: CGFloat = 0.15

    // ---------------------------------------------------------
    // Main Entry
    // ---------------------------------------------------------

    func analyze(
        pixelBuffer: CVPixelBuffer,
        roi: CGRect,
        timestamp: Double
    ) -> StreakObservation? {

        // NOTE:
        // This is intentionally simple and explicit.
        // Replace internals later — logs stay stable.

        guard let streak = extractDominantStreak(
            pixelBuffer: pixelBuffer,
            roi: roi,
            timestamp: timestamp
        ) else {
            Log.info(.shot, "STREAK none_detected")
            return nil
        }

        // ---------------------------
        // Rejection logic (logged)
        // ---------------------------

        if streak.rowSpan < minRowSpan {
            return rejected(streak, "row_span_too_small")
        }

        if streak.localityRatio > maxLocalityRatio {
            return rejected(streak, "too_global_flicker_like")
        }

        if streak.orientationVariance > maxOrientationVariance {
            return rejected(streak, "orientation_incoherent")
        }

        return streak
    }

    // ---------------------------------------------------------
    // Internal helpers
    // ---------------------------------------------------------

    private func extractDominantStreak(
        pixelBuffer: CVPixelBuffer,
        roi: CGRect,
        timestamp: Double
    ) -> StreakObservation? {

        // PLACEHOLDER extraction logic
        // This intentionally favors clarity over cleverness.

        // For now, assume upstream provides:
        // - detected streak mask
        // - fitted orientation
        // - bounding geometry

        // Replace with real extraction later.

        return StreakObservation(
            centroid: CGPoint(x: roi.midX, y: roi.midY),
            lengthPx: 120,
            widthPx: 18,
            orientationRad: 0.35,
            rowSpan: 14,
            orientationVariance: 0.06,
            localityRatio: 0.18,
            frameTimestamp: timestamp,
            confidenceScore: 0.72,
            rejectionReason: nil
        )
    }

    private func rejected(
        _ streak: StreakObservation,
        _ reason: String
    ) -> StreakObservation {

        Log.info(
            .shot,
            String(
                format:
                "STREAK_REJECT reason=%@ len=%.1f rows=%d orientVar=%.2f local=%.2f",
                reason,
                streak.lengthPx,
                streak.rowSpan,
                streak.orientationVariance,
                streak.localityRatio
            )
        )

        return StreakObservation(
            centroid: streak.centroid,
            lengthPx: streak.lengthPx,
            widthPx: streak.widthPx,
            orientationRad: streak.orientationRad,
            rowSpan: streak.rowSpan,
            orientationVariance: streak.orientationVariance,
            localityRatio: streak.localityRatio,
            frameTimestamp: streak.frameTimestamp,
            confidenceScore: 0.0,
            rejectionReason: reason
        )
    }
}
