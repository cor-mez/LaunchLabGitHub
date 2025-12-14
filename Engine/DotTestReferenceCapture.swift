// DotTestReferenceCapture.swift

import Foundation
import CoreGraphics

struct ThresholdSet: Codable {
    var fast9ThresholdY: Int
    var fast9ThresholdCb: Int
    var fast9ScoreMinY: Int
    var fast9ScoreMinCb: Int
    var fast9NmsRadius: Int
    var maxCorners: Int
    var srScale: Float
    var roiScale: CGFloat
    var roiOffsetX: CGFloat
    var roiOffsetY: CGFloat
}

struct ReferenceScene: Codable, Identifiable {
    var id = UUID()
    var cpuCorners: [CGPoint]
    var gpuCorners: [CGPoint]
    var roi: CGRect
    var thresholds: ThresholdSet
    var timestamp: Date
}

@MainActor
final class DotTestReferenceCapture: ObservableObject {

    static let shared = DotTestReferenceCapture()

    @Published var scenes: [ReferenceScene] = []

    private let mode = DotTestMode.shared

    private init() {
        loadReferenceScenes()
    }

    private var saveDirectory: URL {
        let base = FileManager.default.urls(for: .documentDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("DotTestReferenceScenes",
                                           isDirectory: true)
    }

    func saveReferenceScene() {
        let roi = DotTestCoordinator.shared.currentROI()
        let cpu = mode.cpuCorners
        let gpu = mode.gpuCorners

        let thresholds = ThresholdSet(
            fast9ThresholdY: mode.fast9ThresholdY,
            fast9ThresholdCb: mode.fast9ThresholdCb,
            fast9ScoreMinY: mode.fast9ScoreMinY,
            fast9ScoreMinCb: mode.fast9ScoreMinCb,
            fast9NmsRadius: mode.fast9NmsRadius,
            maxCorners: mode.maxCorners,
            srScale: mode.srScale,
            roiScale: mode.roiScale,
            roiOffsetX: mode.roiOffsetX,
            roiOffsetY: mode.roiOffsetY
        )

        let scene = ReferenceScene(cpuCorners: cpu,
                                   gpuCorners: gpu,
                                   roi: roi,
                                   thresholds: thresholds,
                                   timestamp: Date())

        scenes.append(scene)
        persist()
    }

    func loadReferenceScenes() {
        scenes.removeAll()

        let dir = saveDirectory

        if FileManager.default.fileExists(atPath: dir.path) == false {
            try? FileManager.default.createDirectory(at: dir,
                                                     withIntermediateDirectories: true)
            return
        }

        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: []
        )) ?? []

        for f in files {
            if let data = try? Data(contentsOf: f),
               let scene = try? JSONDecoder().decode(ReferenceScene.self, from: data) {
                scenes.append(scene)
            }
        }
    }

    func persist() {
        let dir = saveDirectory

        if FileManager.default.fileExists(atPath: dir.path) == false {
            try? FileManager.default.createDirectory(at: dir,
                                                     withIntermediateDirectories: true)
        }

        for scene in scenes {
            let url = dir.appendingPathComponent(scene.id.uuidString + ".json")
            if let data = try? JSONEncoder().encode(scene) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    func exportReferenceSceneJSON(scene: ReferenceScene) -> Data? {
        try? JSONEncoder().encode(scene)
    }
}
