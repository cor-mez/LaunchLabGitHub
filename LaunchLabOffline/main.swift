import Foundation

print("🚀 LaunchLabOffline starting")

let videoPath = "/Users/Home/Downloads/LaunchLabMoives/imgcaptesth264.mov"
let videoURL  = URL(fileURLWithPath: videoPath)

Log.info(.shot, "MAIN_ABOUT_TO_CREATE_RUNNER")

let pipeline = VisionPipeline()

do {
    let runner = try OfflineVideoRunner(
        videoURL: videoURL,
        pipeline: pipeline
    )

    Log.info(.shot, "MAIN_RUNNER_CREATED")

    runner.start()

    Log.info(.shot, "MAIN_RUNNER_STARTED")

    while runner.step() {
        // stepping deterministically
    }

    Log.info(.shot, "MAIN_RUN_COMPLETE")

} catch {
    Log.info(.shot, "MAIN_ERROR \(error)")
}

exit(0)
