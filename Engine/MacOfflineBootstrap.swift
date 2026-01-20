//
//  MacOfflineBootstrap.swift
//  LaunchLabOffline
//
//  Auto-runs offline VisionPipeline on a .mov file
//

import Foundation

final class MacOfflineBootstrap {

    static func run() {

        let videoPath = "/Users/Home/Downloads/LaunchLabMovies/test.mov"
        let videoURL  = URL(fileURLWithPath: videoPath)

        Log.info(.shot, "OFFLINE_ANALYSIS_BEGIN \(videoPath)")

        let pipeline = VisionPipeline()

        do {
            let runner = try OfflineVideoRunner(
                videoURL: videoURL,
                pipeline: pipeline
            )

            runner.start()

            var frameCount = 0

            while runner.step() {
                frameCount += 1
            }

            Log.info(.shot, "OFFLINE_ANALYSIS_COMPLETE frames=\(frameCount)")

        } catch {
            Log.info(.shot, "OFFLINE_ANALYSIS_FAILED \(error)")
        }
    }
}
