// DotTestTuningPanel.swift

import SwiftUI

struct DotTestTuningPanel: View {

    @ObservedObject private var mode: DotTestMode = DotTestMode.shared
    @State private var showTelemetry = true

    var body: some View {
        VStack {
            ScrollView {
                VStack(spacing: 20) {

                    // MARK: - Backend Picker
                    Picker("Backend", selection: $mode.backend) {
                        ForEach(DotTestMode.Backend.allCases, id: \.self) { b in
                            Text(b.rawValue).tag(b)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())

                    // MARK: - Debug Surface Picker
                    Picker("Debug Surface", selection: $mode.debugSurface) {
                        ForEach(DotTestMode.DebugSurface.allCases, id: \.self) { d in
                            Text(d.rawValue).tag(d)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())


                    // MARK: - FAST9 Controls
                    Group {
                        Text("FAST9 Y Threshold: \(mode.fast9ThresholdY)")
                        Slider(
                            value: Binding(
                                get: { Double(mode.fast9ThresholdY) },
                                set: { mode.fast9ThresholdY = Int($0) }
                            ),
                            in: 1...60
                        )

                        Text("FAST9 Cb Threshold: \(mode.fast9ThresholdCb)")
                        Slider(
                            value: Binding(
                                get: { Double(mode.fast9ThresholdCb) },
                                set: { mode.fast9ThresholdCb = Int($0) }
                            ),
                            in: 1...60
                        )

                        Text("Score Min Y: \(mode.fast9ScoreMinY)")
                        Slider(
                            value: Binding(
                                get: { Double(mode.fast9ScoreMinY) },
                                set: { mode.fast9ScoreMinY = Int($0) }
                            ),
                            in: 0...30
                        )

                        Text("Score Min Cb: \(mode.fast9ScoreMinCb)")
                        Slider(
                            value: Binding(
                                get: { Double(mode.fast9ScoreMinCb) },
                                set: { mode.fast9ScoreMinCb = Int($0) }
                            ),
                            in: 0...30
                        )

                        Text("NMS Radius: \(mode.fast9NmsRadius)")
                        Slider(
                            value: Binding(
                                get: { Double(mode.fast9NmsRadius) },
                                set: { mode.fast9NmsRadius = Int($0) }
                            ),
                            in: 0...5
                        )

                        Text("Max Corners: \(mode.maxCorners)")
                        Slider(
                            value: Binding(
                                get: { Double(mode.maxCorners) },
                                set: { mode.maxCorners = Int($0) }
                            ),
                            in: 50...1000
                        )
                    }


                    // MARK: - ROI Controls
                    Group {
                        Text("ROI Scale: \(mode.roiScale, specifier: "%.2f")")
                        Slider(value: $mode.roiScale, in: 0.5...2.5)

                        Text("ROI Offset X: \(mode.roiOffsetX, specifier: "%.1f")")
                        Slider(value: $mode.roiOffsetX, in: -200...200)

                        Text("ROI Offset Y: \(mode.roiOffsetY, specifier: "%.1f")")
                        Slider(value: $mode.roiOffsetY, in: -200...200)
                    }


                    // MARK: - SR Scale
                    Picker("SR Scale", selection: $mode.srScale) {
                        Text("1×").tag(Float(1.0))
                        Text("1.5×").tag(Float(1.5))
                        Text("2×").tag(Float(2.0))
                        Text("3×").tag(Float(3.0))
                    }
                    .pickerStyle(SegmentedPickerStyle())


                    // MARK: - Toggles
                    Toggle("Show Vectors", isOn: $mode.showVectors)
                    Toggle("Show Heatmap", isOn: $mode.showHeatmap)


                    // MARK: - Telemetry Toggle
                    Toggle("Show Telemetry", isOn: $showTelemetry)
                        .padding(.top, 10)

                    if showTelemetry {
                        DotTestTuningTelemetryBlock()
                    }
                }
                .padding()
            }
        }
        .frame(maxWidth: 300)
        .background(Color.black.opacity(0.85))
    }
}


// MARK: - Telemetry Block

struct DotTestTuningTelemetryBlock: View {

    @ObservedObject private var mode: DotTestMode = DotTestMode.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            Text("CPU Corners: \(mode.cpuCornerCount)")
                .foregroundColor(.white)

            Text("GPU Corners: \(mode.gpuCornerCount)")
                .foregroundColor(.white)

            Text("Matches: \(mode.matchCount)")
                .foregroundColor(.white)

            Text("CPU Only: \(mode.cpuOnlyCorners.count)")
                .foregroundColor(.white)

            Text("GPU Only: \(mode.gpuOnlyCorners.count)")
                .foregroundColor(.white)

            Text("Avg Score: \(mode.avgGpuScore, specifier: "%.2f")")
                .foregroundColor(.white)

            Text("Min Score: \(mode.minGpuScore, specifier: "%.2f")")
                .foregroundColor(.white)

            Text("Max Score: \(mode.maxGpuScore, specifier: "%.2f")")
                .foregroundColor(.white)

            Text("Avg Spatial Error: \(mode.avgSpatialError, specifier: "%.2f") px")
                .foregroundColor(.white)

            Text("Max Spatial Error: \(mode.maxSpatialError, specifier: "%.2f") px")
                .foregroundColor(.white)

            Text("NMS Cluster Size: \(mode.nmsClusterSize)")
                .foregroundColor(.white)
        }
        .foregroundColor(.white)
        .padding()
        .background(Color.gray.opacity(0.3))
        .cornerRadius(8)
    }
}


struct DotTestTuningPanel_Previews: PreviewProvider {
    static var previews: some View {
        DotTestTuningPanel()
            .preferredColorScheme(.dark)
    }
}
