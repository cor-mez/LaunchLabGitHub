//
//  DotTestReferenceCapture.swift
//

import Foundation
import CoreGraphics

// MARK: - Threshold Bundle
struct ThresholdSet: Codable, Equatable {
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

// MARK: - Reference Scene Model
struct ReferenceScene: Codable, Identifiable, Equatable {

    var id = UUID()

    var cpuCorners: [CGPoint]
    var gpuCorners: [CGPoint]

    var roi: CGRect
    var thresholds: ThresholdSet

    var timestamp: Date

    // Codable helpers for CGPoint/CGRect
    enum CodingKeys: String, CodingKey {
        case id
        case cpuCorners
        case gpuCorners
        case roi
        case thresholds
        case timestamp
    }
}


// MARK: - Capture Manager

@MainActor
final class DotTestReferenceCapture: ObservableObject {

    static let shared = DotTestReferenceCapture()

    @Published var scenes: [ReferenceScene] = []

    private let mode = DotTestMode.shared
    private let coord = DotTestCoordinator.shared

    private init() {
        loadReferenceScenes()
    }

    // ---------------------------------------------------------------------
    // MARK: - Storage Directory
    // ---------------------------------------------------------------------
    private var saveDirectory: URL {
        let base = FileManager.default.urls(for: .documentDirectory,
                                            in: .userDomainMask)[0]
        let url = base.appendingPathComponent("DotTestReferenceScenes",
                                              isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url,
                                                     withIntermediateDirectories: true)
        }
        return url
    }

    // ---------------------------------------------------------------------
    // MARK: - Save Reference Scene
    // ---------------------------------------------------------------------
    func saveReferenceScene() {

        let cpu = mode.cpuCorners
        let gpu = mode.gpuCorners
        let roi = coord.currentROI()

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

        let scene = ReferenceScene(
            cpuCorners: cpu,
            gpuCorners: gpu,
            roi: roi,
            thresholds: thresholds,
            timestamp: Date()
        )

        scenes.append(scene)
        persistScenes()
    }

    // ---------------------------------------------------------------------
    // MARK: - Load All Scenes
    // ---------------------------------------------------------------------
    func loadReferenceScenes() {
        scenes.removeAll()

        let dir = saveDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: []
        ) else { return }

        for file in files {
            guard file.pathExtension == "json" else { continue }
            if let data = try? Data(contentsOf: file),
               let scene = try? JSONDecoder().decode(ReferenceScene.self, from: data) {
                scenes.append(scene)
            }
        }
    }

    // ---------------------------------------------------------------------
    // MARK: - Persist All Scenes
    // ---------------------------------------------------------------------
    private func persistScenes() {
        let dir = saveDirectory

        for scene in scenes {
            let fileURL = dir.appendingPathComponent(scene.id.uuidString + ".json")
            if let data = try? JSONEncoder().encode(scene) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    // ---------------------------------------------------------------------
    // MARK: - Export
    // ---------------------------------------------------------------------
    func exportReferenceSceneJSON(_ scene: ReferenceScene) -> Data? {
        try? JSONEncoder().encode(scene)
    }
}
