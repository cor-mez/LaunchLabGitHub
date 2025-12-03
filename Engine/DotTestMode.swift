//
//  DotTestMode.swift (Clean 2025 Edition)
//  LaunchLab
//

import SwiftUI
import AVFoundation
import CoreVideo
import CoreImage

struct DotTestMode: View {

    @EnvironmentObject var camera: CameraManager
    @StateObject private var coordinator = DotTestCoordinator()

    // MARK: - Detector tuning state

    @State private var useBlueChannel: Bool = true
    @State private var useSuperResolution: Bool = true
    @State private var preFilterGain: Double = 1.35
    @State private var fast9Threshold: Double = 14
    @State private var vImageThreshold: Double = 30

    @State private var srScaleIndex: Int = 2     // default = 2.0×
    private let srScales: [Float] = [1.0, 1.5, 2.0, 3.0]

    @State private var showClusterDebug: Bool = false

    var body: some View {
        VStack(spacing: 10) {

            // ------------------------------
            // Preview + overlay
            // ------------------------------
            DotTestPreviewView(coordinator: coordinator)
                .aspectRatio(9.0/16.0, contentMode: .fit)
                .background(Color.black)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CNT = \(coordinator.detectedCount)")
                        Text(String(format: "Y-bright = %.2f", coordinator.averageBrightness))
                        Text("ROI = \(Int(coordinator.roiSize.width))×\(Int(coordinator.roiSize.height))")
                    }
                    .font(.caption.monospacedDigit())
                    .padding(6)
                    .background(.black.opacity(0.6))
                    .cornerRadius(5)
                    .padding(6)
                }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {

                    HStack {
                        Button("Freeze Frame") { coordinator.freezeFrame() }
                            .buttonStyle(.borderedProminent)

                        Button("Unfreeze") { coordinator.unfreeze() }
                            .buttonStyle(.bordered)
                    }

                    Button("Run Detection") {
                        coordinator.overlayLayer.showClusterDebug = showClusterDebug
                        coordinator.runDetection(with: currentConfig)
                    }
                    .buttonStyle(.bordered)

                    Divider()

                    Toggle("Use Blue Channel", isOn: $useBlueChannel)
                    Toggle("Use Super Resolution", isOn: $useSuperResolution)
                    Toggle("Show Cluster Debug", isOn: $showClusterDebug)

                    Text("FAST9 Threshold: \(Int(fast9Threshold))")
                    Slider(value: $fast9Threshold, in: 4...40, step: 1)

                    Text("vImage Threshold: \(Int(vImageThreshold))")
                    Slider(value: $vImageThreshold, in: 5...80, step: 1)

                    Text(String(format: "Pre-filter Gain: %.2f", preFilterGain))
                    Slider(value: $preFilterGain, in: 0.8...2.0, step: 0.05)

                    Picker("SR Scale", selection: $srScaleIndex) {
                        ForEach(0..<srScales.count, id: \.self) { idx in
                            Text(String(format: "%.1fx", srScales[idx])).tag(idx)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .padding(.horizontal, 12)
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            coordinator.attach(camera: camera)

            // Connect coordinator dimension callback for mapper installation
            coordinator.onDimensions = { w, h in
                let mapper = OverlayMapper(
                    bufferWidth: w,
                    bufferHeight: h,
                    viewSize: coordinator.overlayLayer.bounds.size,
                    previewLayer: .nil                   // DotTest does NOT use previewLayer
                )
                coordinator.overlayLayer.assignMapper(mapper)
            }
        }
    }

    // MARK: - Config Mapping

    private var currentConfig: DotDetectorConfig {
        DotDetectorConfig(
            fast9Threshold: Int(fast9Threshold),
            vImageThreshold: Float(vImageThreshold),
            preFilterGain: Float(preFilterGain),
            blueChromaGain: 4.0,
            useBlueChannel: useBlueChannel,
            useSuperResolution: useSuperResolution,
            srScaleOverride: srScales[srScaleIndex],
            debugShowYROI: false,
            debugShowBlueROI: false,
            debugShowNormalizedBlue: false
        )
    }
}

//
//  DOT TEST PREVIEW VIEW
//

private struct DotTestPreviewView: UIViewRepresentable {

    @ObservedObject var coordinator: DotTestCoordinator

    func makeUIView(context: Context) -> DotTestPreviewContainerView {
        let view = DotTestPreviewContainerView()

        // Overlay must follow the view’s frame
        coordinator.overlayLayer.frame = view.bounds
        view.layer.addSublayer(coordinator.overlayLayer)

        return view
    }

    func updateUIView(_ uiView: DotTestPreviewContainerView, context: Context) {
        let buffer = coordinator.frozenBuffer ?? coordinator.liveBuffer
        uiView.updateImage(with: buffer)

        coordinator.overlayLayer.frame = uiView.bounds
    }
}

//
//  DotTestPreviewContainerView (CIImage-backed)
//

private final class DotTestPreviewContainerView: UIView {

    private let imageView = UIImageView()
    private let ciContext = CIContext()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = .black

        imageView.contentMode = .scaleAspectFit
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.frame = bounds
        addSubview(imageView)
    }

    func updateImage(with pixelBuffer: CVPixelBuffer?) {
        guard let buffer = pixelBuffer else {
            imageView.image = nil
            return
        }

        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let cg = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            imageView.image = nil
            return
        }

        imageView.image = UIImage(cgImage: cg)
    }
}
