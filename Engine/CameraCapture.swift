import AVFoundation
import CoreVideo
import UIKit

final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "camera.capture.queue")

    var onFrame: ((CVPixelBuffer) -> Void)?

    override init() {
        super.init()
        configure()
    }

    private func configure() {
        session.beginConfiguration()

        if session.canSetSessionPreset(.inputPriority) {
            session.sessionPreset = .inputPriority
        } else if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .back) else {
            return
        }

        let format = device.formats.first { f in
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            return d.width == 1920 && d.height == 1080
        }

        if let f = format {
            try? device.lockForConfiguration()
            device.activeFormat = f
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 240)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 240)
            device.unlockForConfiguration()
        }

        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
                                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)

        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        session.commitConfiguration()
    }

    func start() {
        if session.isRunning == false {
            session.startRunning()
        }
    }

    func stop() {
        if session.isRunning {
            session.stopRunning()
        }
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection)
    {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pb)
    }
}