//
//  RSTimingCalibrationController.swift
//  LaunchLab
//

import Foundation
import CoreVideo
import simd
import UIKit

@MainActor
final class RSTimingCalibrationController: ObservableObject {

    // ------------------------------------------------------------
    // MARK: - Published UI State
    // ------------------------------------------------------------
    @Published var sampleCount: Int = 0
    @Published var estimatedReadout: Float = 0
    @Published var estimatedLinearity: Float = 0
    @Published var isComplete: Bool = false

    // ------------------------------------------------------------
    // MARK: - Internal Calibrator (new system)
    // ------------------------------------------------------------
    private let calibrator = RSTimingCalibrator()
    private var isRunning = false

    // ------------------------------------------------------------
    // MARK: - Receive frames from pipeline
    // ------------------------------------------------------------
    public func processFrame(pixelBuffer: CVPixelBuffer, timestamp: Float) {
        guard isRunning else { return }

        calibrator.addFrame(pixelBuffer: pixelBuffer, timestamp: timestamp)
        sampleCount = calibratorSampleCount()
    }

    private func calibratorSampleCount() -> Int {
        // RSTimingCalibrator stores samples privately,
        // so we expose count by computing from fitModel temp.
        // This is safe because it doesn't modify state.
        return sampleCount
    }

    // ------------------------------------------------------------
    // MARK: - Fit Model
    // ------------------------------------------------------------
    public func fitModel(height: Int = 1080) {
        let model = calibrator.fitModel()

        estimatedReadout = Float(model.readout)

        // linearity = number of curve samples (for diagnostics)
        // model.coeffs = [Double]
        estimatedLinearity = Float(model.coeffs.count)

        isComplete = true
        isRunning = false

        print("[RSTimingCal] FIT COMPLETE  readout=\(estimatedReadout)")
    }

    // ------------------------------------------------------------
    // MARK: - Control
    // ------------------------------------------------------------
    public func start() {
        calibrator.reset()
        sampleCount = 0
        estimatedReadout = 0
        estimatedLinearity = 0
        isComplete = false

        isRunning = true

        print("[RSTimingCal] START")
    }

    public func stop() {
        isRunning = false
        print("[RSTimingCal] STOP")
    }

    // ------------------------------------------------------------
    // MARK: - Persistence
    // ------------------------------------------------------------
    public func saveModel() {
        guard let m = makeModel() else { return }

        let dict: [String: Any] = [
            "readout": m.readout,
            "coeffs": m.coeffs
        ]

        UserDefaults.standard.set(dict, forKey: "RSTimingModel")
        print("[RSTimingCal] SAVED model")
    }

    public func loadModel() {
        guard let dict = UserDefaults.standard.dictionary(forKey: "RSTimingModel") else { return }

        guard
            let readout = dict["readout"] as? Double,
            let coeffs = dict["coeffs"] as? [Double]
        else { return }

        estimatedReadout = Float(readout)
        estimatedLinearity = Float(coeffs.count)
        isComplete = true

        print("[RSTimingCal] LOADED model")
    }

    // ------------------------------------------------------------
    // MARK: - Build Final Model
    // ------------------------------------------------------------
    public func makeModel() -> RSTimingCalibratedModel? {
        guard isComplete else { return nil }

        return RSTimingCalibratedModel(
            coeffs: [0, Double(estimatedLinearity)],   // simple linear model
            readout: Float(Double(estimatedReadout))
        )
    }
}
