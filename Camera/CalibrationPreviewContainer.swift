//
//  CalibrationPreviewContainer.swift
//  LaunchLab
//

import UIKit
import AVFoundation
import simd

final class CalibrationPreviewContainer: UIView {

    private weak var camera: CameraManager?
    private weak var controller: RSTimingCalibrationController?

    private let previewLayer = AVCaptureVideoPreviewLayer()
    private let calibrationLayer = RSTimingCalibrationOverlay()

    init(controller: RSTimingCalibrationController,
         camera: CameraManager)
    {
        self.controller = controller
        self.camera = camera
        super.init(frame: .zero)
        setupPreview()
        setupOverlay()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupPreview() {
        guard let camera else { return }
        previewLayer.session = camera.cameraSession
        previewLayer.videoGravity = .resizeAspect
        layer.addSublayer(previewLayer)
    }

    private func setupOverlay() {
        calibrationLayer.contentsScale = UIScreen.main.scale
        layer.addSublayer(calibrationLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        previewLayer.frame = bounds
        calibrationLayer.frame = bounds

        CATransaction.commit()
    }

    func updateOverlay() {
        guard let controller else { return }

        let samples = controller.samples
        let curve = controller.curve
        let readout = controller.readout

        var maxRow: Float = 1
        if let cam = camera {
            maxRow = Float(cam.height)
        }

        calibrationLayer.update(samples: samples,
                                curve: curve,
                                readout: readout,
                                maxRow: maxRow)
    }
}