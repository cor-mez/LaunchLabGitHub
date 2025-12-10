// DotTestMode.swift v4A

import SwiftUI
import CoreVideo
import AVFoundation

struct DotTestMode: View {

    @EnvironmentObject var camera: CameraManager
    @StateObject private var coordinator = DotTestCoordinator()

    @State private var backend: DetectorBackend = .cpu
    @State private var debugSurface: DotTestDebugSurface = .none

    @State private var showPreFAST9: Bool = false
    @State private var showSRFAST9: Bool = false

    @State private var fast9Threshold: Double = 14.0
    @State private var vImageThreshold: Double = 30.0
    @State private var preFilterGain: Double = 1.35

    @State private var srScaleIndex: Int = 1
    private let srScales: [Float] = [1.0, 1.5, 2.0, 3.0]

    @State private var roiScale: CGFloat = 0.40

    var body: some View {
        VStack(spacing: 10) {

            DotTestPreviewView(
                coordinator: coordinator,
                debugSurface: debugSurface,
                showPreFAST9: showPreFAST9,
                showSRFAST9: showSRFAST9
            )
            .aspectRatio(9/16, contentMode: .fit)
            .background(Color.black)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CPU CNT = \(coordinator.detectedCountCPU)")
                    Text("GPU CNT = \(coordinator.detectedCountGPU)")
                    Text(String(format: "YBright = %.2f", coordinator.averageBrightness))
                    Text("ROI = \(Int(coordinator.roiSize.width))×\(Int(coordinator.roiSize.height))")
                }
                .font(.caption.monospacedDigit())
                .padding(6)
                .background(Color.black.opacity(0.6))
                .cornerRadius(6)
                .padding([.top, .leading], 8)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    HStack {
                        Button("Freeze Frame") { coordinator.freezeFrame() }
                            .buttonStyle(.borderedProminent)
                        Button("Unfreeze") { coordinator.unfreeze() }
                            .buttonStyle(.bordered)
                    }

                    Button("Run Detection") {
                        coordinator.runDetection(
                            with: currentConfig,
                            roiScale: roiScale,
                            backend: backend
                        )
                    }
                    .buttonStyle(.bordered)

                    Picker("Detector Backend", selection: $backend) {
                        Text("CPU").tag(DetectorBackend.cpu)
                        Text("GPU-Y").tag(DetectorBackend.gpuY)
                        Text("GPU-Cb").tag(DetectorBackend.gpuCb)
                    }
                    .pickerStyle(.segmented)

                    Picker("Debug Surface", selection: $debugSurface) {
                        Text("None").tag(DotTestDebugSurface.none)
                        Text("Y-Norm").tag(DotTestDebugSurface.yNorm)
                        Text("Y-Edge").tag(DotTestDebugSurface.yEdge)
                        Text("Cb-Edge").tag(DotTestDebugSurface.cbEdge)
                        Text("FAST9").tag(DotTestDebugSurface.fast9)
                    }
                    .pickerStyle(.segmented)

                    Toggle("Show Pre-FAST9 Planar", isOn: $showPreFAST9)
                    Toggle("Show SR-FAST9 Planar", isOn: $showSRFAST9)

                    Text("FAST9 Threshold: \(Int(fast9Threshold))")
                    Slider(value: $fast9Threshold, in: 4...40, step: 1)

                    Text("vImage Threshold: \(Int(vImageThreshold))")
                    Slider(value: $vImageThreshold, in: 5...80, step: 1)

                    Text("Pre-filter Gain: \(String(format: \"%.2f\", preFilterGain))")
                    Slider(value: $preFilterGain, in: 0.8...2.0, step: 0.05)

                    Text("SR Scale")
                    Picker("SR", selection: $srScaleIndex) {
                        ForEach(0..<srScales.count, id: \.self) { i in
                            Text(String(format: "%.1fx", srScales[i])).tag(i)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("ROI Scale: \(String(format: \"%.2f\", roiScale))")
                    Slider(value: $roiScale, in: 0.10...0.80, step: 0.05)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 20)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            coordinator.attach(camera: camera)
        }
    }

    private var currentConfig: DotDetectorConfig {
        DotDetectorConfig(
            fast9Threshold: Int(fast9Threshold),
            vImageThreshold: Float(vImageThreshold),
            preFilterGain: Float(preFilterGain),
            blueChromaGain: 4.0,
            useBlueChannel: false,
            blueEnhancement: .off,
            useSuperResolution: true,
            srScaleOverride: srScales[srScaleIndex],
            debugShowYROI: false,
            debugShowBlueROI: false,
            debugShowNormalizedBlue: false
        )
    }
}
