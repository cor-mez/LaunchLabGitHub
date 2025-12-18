 (cd "$(git rev-parse --show-toplevel)" && git apply --3way <<'EOF' 
diff --git a/Engine/RSIntegrationV1.swift b/Engine/RSIntegrationV1.swift
index f702711fe0b91e2851abea15bee7dc1685e664a8..7be3bf4e6fc9bb023bf1c1c2f8df8c08d2b6bea2 100644
--- a/Engine/RSIntegrationV1.swift
+++ b/Engine/RSIntegrationV1.swift
@@ -35,58 +35,51 @@ final class RSIntegrationV1 {
 
     // MARK: - State Storage
 
     private var rsWindowLogState: RSWindowLogState = .idle
 
     // MARK: - Members
 
     private let config: Config
     private let window: RSWindow
     private let solver: RSPnPBridgeV1
 
     // Pose module (observational only -- no downstream use)
     private let rspnpPoseModule = RSPnPMinimalSolveAndPoseStabilityModule(
         config: .init(
             enabled: true,
             confidenceThreshold: 12.0,
             logTransitionsOnly: true
         ),
         poseConfig: .init(
             historySize: 20,
             minSamplesForCorrelation: 8,
             logEveryNSuccesses: 1
         )
     )
 
-    // ------------------------------------------------------------------
-    // IMPACT-CENTERED DYNAMIC OBSERVABILITY (ICDO) -- LOG ONLY
-    // ------------------------------------------------------------------
-
-    private var lastMotionPxPerSec: Double?
-    private var lastCentroid: SIMD2<Double>?
-    private var impactWindowActive = false
-    private var impactStartTimeSec: Double?
+    private let icdoModule = ImpactCenteredDynamicObservabilityModule()
 
     // MARK: - Init
 
     init(config: Config = Config()) {
         self.config = config
         self.window = RSWindow()
         self.solver = RSPnPBridgeV1(
             config: RSPnPConfig(
                 minFrames: config.minFrames,
                 requireRowTiming: false
             )
         )
     }
 
     // MARK: - RSWindow Logging
 
     private func logRSWindow(
         _ newState: RSWindowLogState,
         _ message: String
     ) {
         guard DebugProbe.isEnabled(.capture) else { return }
         guard newState != rsWindowLogState else { return }
         rsWindowLogState = newState
         print(message)
     }
@@ -104,147 +97,93 @@ final class RSIntegrationV1 {
         // 1️⃣ Confidence gate
         guard smoothedBallLockCount >= config.confidenceThreshold else {
             logRSWindow(
                 .rejectedLowConfidence,
                 "[RSWINDOW] rejected conf=\(fmt(smoothedBallLockCount)) < \(fmt(config.confidenceThreshold))"
             )
             return
         }
 
         // 2️⃣ Feed RSWindow
         window.ingest(
             ballCenter2D: ballCenter2D,
             ballRadiusPx: ballRadiusPx,
             timestampSec: timestampSec,
             confidence: smoothedBallLockCount
         )
 
         logRSWindow(
             .accepted(count: window.frameCount),
             "[RSWINDOW] accepted t=\(fmt(timestampSec)) count=\(window.frameCount)"
         )
 
         // 3️⃣ Snapshot + validity gate
         let snapshot = window.snapshot(nowSec: timestampSec)
 
+        icdoModule.observe(
+            ICDOObservation(
+                timestampSec: timestampSec,
+                frameIndex: snapshot.frameCount,
+                centroidPx: SIMD2<Double>(Double(ballCenter2D.x), Double(ballCenter2D.y)),
+                ballRadiusPx: Double(ballRadiusPx),
+                compactness: nil,
+                densityCount: nil,
+                fast9Points: nil,
+                scanlineMotionProfile: nil,
+                ballLockConfidence: smoothedBallLockCount,
+                mdgAccepted: nil,
+                rsWindowValid: snapshot.isValid,
+                rowTiming: snapshot.frames.last?.rowTiming
+            )
+        )
+
         guard snapshot.isValid else {
             let reason: String
             if snapshot.stalenessSec > config.maxStalenessSec {
                 reason = "stale \(fmt(snapshot.stalenessSec))s"
             } else if snapshot.spanSec > config.maxSpanSec {
                 reason = "span \(fmt(snapshot.spanSec))s"
             } else {
                 reason = "insufficient frames"
             }
 
             logRSWindow(.windowInvalid(reason: reason),
                         "[RSWINDOW] invalid \(reason)")
             return
         }
 
         logRSWindow(
             .windowReady(count: snapshot.frameCount),
             "[RSWINDOW] ready frames=\(snapshot.frameCount) span=\(fmt(snapshot.spanSec))s"
         )
 
-        // ------------------------------------------------------------------
-        // 4️⃣ ICDO -- Impact-Centered Dynamic Observability (LOG ONLY)
-        // ------------------------------------------------------------------
-
-        if DebugProbe.isEnabled(.capture) {
-
-            let centroid = SIMD2<Double>(
-                Double(ballCenter2D.x),
-                Double(ballCenter2D.y)
-            )
-
-            let motionDelta = (lastMotionPxPerSec != nil && motionPxPerSec != nil)
-                ? abs(motionPxPerSec! - lastMotionPxPerSec!)
-                : nil
-
-            let centroidJump = (lastCentroid != nil)
-                ? simd_length(centroid - lastCentroid!)
-                : nil
-
-            // Candidate start (no thresholds -- multi-signal presence only)
-            if !impactWindowActive,
-               motionDelta != nil || centroidJump != nil {
-
-                impactWindowActive = true
-                impactStartTimeSec = timestampSec
-
-                print("[IMPACT] candidate start frame=\(snapshot.frameCount)")
-                print("[IMPACT] trigger signals=" +
-                      "motionΔ=\(fmt(motionDelta)) " +
-                      "centroidJump=\(fmt(centroidJump))")
-            }
-
-            // During candidate window
-            if impactWindowActive {
-
-                let spanMs = (timestampSec - (impactStartTimeSec ?? timestampSec)) * 1000.0
-
-                print("[IMPACT] candidate span_ms=\(fmt(spanMs))")
-
-                // Geometry observation (pre/during/post will be inferred offline)
-                print("[IMPACT][GEOM] radius_px=\(fmt(ballRadiusPx)) " +
-                      "frameCount=\(snapshot.frameCount)")
-
-                // Confidence continuity
-                print("[IMPACT][CONF] ballLock=\(fmt(smoothedBallLockCount)) " +
-                      "rsWindowValid=\(snapshot.isValid)")
-
-                // Rolling-shutter placeholders (no assumptions)
-                print("[RS] shear_peak=n/a temporal_asymmetry=n/a scanline_motion_profile=n/a")
-            }
-
-            // End window automatically when motion settles (no thresholds)
-            if impactWindowActive,
-               motionPxPerSec != nil,
-               lastMotionPxPerSec != nil,
-               abs(motionPxPerSec! - lastMotionPxPerSec!) < 1e-6 {
-
-                impactWindowActive = false
-                impactStartTimeSec = nil
-                print("[IMPACT] candidate end")
-            }
-
-            lastMotionPxPerSec = motionPxPerSec
-            lastCentroid = centroid
-        }
-
         // ------------------------------------------------------------------
         // 5️⃣ Minimal RS-PnP solve + pose observation (unchanged)
         // ------------------------------------------------------------------
 
         rspnpPoseModule.evaluate(
             nowSec: timestampSec,
             ballLockConfidence: smoothedBallLockCount,
             window: snapshot,
             motionPxPerSec: motionPxPerSec,
             solve: { window in
                 let outcome = self.solver.process(window: window)
 
                 guard case let .success(pose, residual, conditioning) = outcome else {
                     throw NSError(domain: "RSPnP", code: -1)
                 }
 
                 return (pose, residual, conditioning)
             }
         )
     }
 
     // MARK: - Formatting
 
-    private func fmt(_ v: Double?) -> String {
-        guard let v else { return "n/a" }
-        return String(format: "%.3f", v)
-    }
-
     private func fmt(_ v: Double) -> String {
         String(format: "%.3f", v)
     }
 
     private func fmt(_ v: Float) -> String {
         String(format: "%.2f", v)
     }
 }
 
EOF
)