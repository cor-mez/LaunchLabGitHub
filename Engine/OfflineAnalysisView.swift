//
//  OfflineAnalysisView.swift
//  LaunchLab
//

import SwiftUI

struct OfflineAnalysisView: View {

    let videoURL: URL

    @State private var runner: OfflineVideoRunner?
    @State private var hasMoreFrames = true

    private let pipeline = VisionPipeline()

    var body: some View {
        VStack(spacing: 12) {

            Text(videoURL.lastPathComponent)
                .font(.headline)

            HStack {
                Button("Start") {
                    do {
                        runner = try OfflineVideoRunner(
                            videoURL: videoURL,
                            pipeline: pipeline
                        )
                        runner?.start()
                        hasMoreFrames = true
                    } catch {
                        Log.info(.shot, "Failed to start offline runner: \(error)")
                    }
                }

                Button("Step Frame") {
                    if let ok = runner?.step() {
                        hasMoreFrames = ok
                    }
                }
                .disabled(!hasMoreFrames)

                Button("Run 10 Frames") {
                    guard let runner else { return }
                    for _ in 0..<10 {
                        if !runner.step() {
                            hasMoreFrames = false
                            break
                        }
                    }
                }
                .disabled(!hasMoreFrames)
            }

            Spacer()

            Text("Check console logs for RS_FRAME / rejection reasons")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}
