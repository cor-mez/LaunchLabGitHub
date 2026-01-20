//
//  OfflineVideoRunner.swift
//  LaunchLab
//
//  Deterministic offline video → VisionPipeline bridge
//

import AVFoundation
import CoreVideo
import Foundation
import CoreGraphics

final class OfflineVideoRunner {

    private let asset: AVAsset
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private let pipeline: VisionPipeline

    private var frameIndex: Int = 0

    // -------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------

    init(videoURL: URL, pipeline: VisionPipeline) throws {

        self.pipeline = pipeline

        // Force precise timing + track loading
        self.asset = AVURLAsset(
            url: videoURL,
            options: [
                AVURLAssetPreferPreciseDurationAndTimingKey: true
            ]
        )

        // ---------------------------------------------------------
        // Explicitly load tracks (CRITICAL)
        // ---------------------------------------------------------

        let semaphore = DispatchSemaphore(value: 0)
        var videoTracks: [AVAssetTrack] = []
        var loadError: Error?

        let assetRef = self.asset  // 👈 capture local reference, not self

        assetRef.loadValuesAsynchronously(forKeys: ["tracks", "duration"]) {
            var err: NSError?

            let trackStatus = assetRef.statusOfValue(forKey: "tracks", error: &err)
            let durationStatus = assetRef.statusOfValue(forKey: "duration", error: &err)

            if trackStatus == .loaded && durationStatus == .loaded {
                videoTracks = assetRef.tracks(withMediaType: .video)
            } else {
                loadError = err
            }

            semaphore.signal()
        }

        semaphore.wait()

        if let error = loadError {
            throw error
        }

        Log.info(
            .shot,
            String(
                format: "ASSET_LOADED duration=%.3fs",
                CMTimeGetSeconds(assetRef.duration)
            )
        )

        Log.info(.shot, "VIDEO_TRACK_COUNT \(videoTracks.count)")

        guard let track = videoTracks.first else {
            throw NSError(
                domain: "OfflineVideoRunner",
                code: -10,
                userInfo: [NSLocalizedDescriptionKey: "No video tracks found after loading"]
            )
        }

        Log.info(
            .shot,
            String(
                format: "VIDEO_TRACK dimensions=%.0fx%.0f nominalFPS=%.1f",
                track.naturalSize.width,
                track.naturalSize.height,
                track.nominalFrameRate
            )
        )

        // ---------------------------------------------------------
        // Reader setup
        // ---------------------------------------------------------

        self.reader = try AVAssetReader(asset: asset)

        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]

        self.output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: outputSettings
        )

        self.output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw NSError(
                domain: "OfflineVideoRunner",
                code: -11,
                userInfo: [NSLocalizedDescriptionKey: "Cannot add track output"]
            )
        }

        reader.add(output)

        Log.info(.shot, "OFFLINE_RUNNER_INIT_COMPLETE")
    }

    // -------------------------------------------------------------
    // MARK: - Start
    // -------------------------------------------------------------

    func start() {
        pipeline.reset()
        frameIndex = 0

        let ok = reader.startReading()
        Log.info(.shot, "READER_START ok=\(ok ? 1 : 0) status=\(reader.status.rawValue)")
    }

    // -------------------------------------------------------------
    // MARK: - Step
    // -------------------------------------------------------------

    func step() -> Bool {

        guard reader.status == .reading else {
            Log.info(.shot, "READER_NOT_READING status=\(reader.status.rawValue)")
            return false
        }

        guard let sampleBuffer = output.copyNextSampleBuffer(),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else {
            Log.info(.shot, "NO_SAMPLE")
            return false
        }

        let ts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let timeSec = CMTimeGetSeconds(ts)

        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)

        let intrinsics = CameraIntrinsics(
            fx: 1.0,
            fy: 1.0,
            cx: Float(w) * 0.5,
            cy: Float(h) * 0.5
        )

        Log.info(.shot, String(
            format: "OFFLINE_FRAME idx=%d t=%.6f w=%d h=%d",
            frameIndex, timeSec, w, h
        ))

        _ = pipeline.processFrame(
            pixelBuffer: pixelBuffer,
            timestamp: timeSec,
            intrinsics: intrinsics
        )

        frameIndex += 1
        return true
    }
}
