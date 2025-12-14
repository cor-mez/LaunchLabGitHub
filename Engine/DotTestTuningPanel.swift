//
//  DotTestTuningPanel.swift
//

import SwiftUI

struct DotTestTuningPanel: View {

    @ObservedObject private var mode = DotTestMode.shared
    @State private var showTelemetry = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {

                // ----------------------------------------------------------
                // MARK: Backend Picker
                // ----------------------------------------------------------
                pickerSection(
                    title: "Detector Backend",
                    selection: $mode.backend,
                    items: DotTestMode.Backend.all,
                    label: { Text($0.name).foregroundColor(.white) }
                )

                // ----------------------------------------------------------
                // MARK: Debug Surface Picker
                // ----------------------------------------------------------
                pickerSection(
                    title: "Debug Surface",
                    selection: $mode.debugSurface,
                    items: DotTestMode.DebugSurface.all,
                    label: { Text($0.name).foregroundColor(.white) }
                )

                // ----------------------------------------------------------
                // MARK: FAST9 Controls
                // ----------------------------------------------------------
                Group {
                    sectionLabel("FAST9 Tuning")

                    tuningSlider(
                        label: "FAST9 Threshold Y",
                        value: Binding(
                            get: { Double(mode.fast9ThresholdY) },
                            set: { mode.fast9ThresholdY = Int($0) }
                        ),
                        range: 1...60
                    )

                    tuningSlider(
                        label: "FAST9 Threshold Cb",
                        value: Binding(
                            get: { Double(mode.fast9ThresholdCb) },
                            set: { mode.fast9ThresholdCb = Int($0) }
                        ),
                        range: 1...60
                    )

                    tuningSlider(
                        label: "Score Min Y",
                        value: Binding(
                            get: { Double(mode.fast9ScoreMinY) },
                            set: { mode.fast9ScoreMinY = Int($0) }
                        ),
                        range: 0...30
                    )

                    tuningSlider(
                        label: "Score Min Cb",
                        value: Binding(
                            get: { Double(mode.fast9ScoreMinCb) },
                            set: { mode.fast9ScoreMinCb = Int($0) }
                        ),
                        range: 0...30
                    )

                    tuningSlider(
                        label: "NMS Radius",
                        value: Binding(
                            get: { Double(mode.fast9NmsRadius) },
                            set: { mode.fast9NmsRadius = Int($0) }
                        ),
                        range: 0...5
                    )

                    tuningSlider(
                        label: "Max Corners",
                        value: Binding(
                            get: { Double(mode.maxCorners) },
                            set: { mode.maxCorners = Int($0) }
                        ),
                        range: 50...1000
                    )
                }

                // ----------------------------------------------------------
                // MARK: ROI Controls
                // ----------------------------------------------------------
                Group {
                    sectionLabel("ROI Controls")

                    tuningSlider(
                        label: "ROI Scale",
                        value: $mode.roiScale,
                        range: 0.5...2.5
                    )

                    tuningSlider(
                        label: "ROI Offset X",
                        value: $mode.roiOffsetX,
                        range: -300...300
                    )

                    tuningSlider(
                        label: "ROI Offset Y",
                        value: $mode.roiOffsetY,
                        range: -300...300
                    )
                }

                // ----------------------------------------------------------
                // MARK: SR Scale
                // ----------------------------------------------------------
                sectionLabel("Super-Resolution")

                Picker("SR Scale", selection: $mode.srScale) {
                    Text("1×").tag(Float(1.0))
                    Text("1.5×").tag(Float(1.5))
                    Text("2×").tag(Float(2.0))
                    Text("3×").tag(Float(3.0))
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                .foregroundColor(.white)

                // ----------------------------------------------------------
                // MARK: Overlays
                // ----------------------------------------------------------
                Group {
                    sectionLabel("Overlay Options")

                    Toggle("Show Vectors", isOn: $mode.showVectors)
                        .foregroundColor(.white)

                    Toggle("Show Heatmap", isOn: $mode.showHeatmap)
                        .foregroundColor(.white)
                }
                .padding(.horizontal)

                // ----------------------------------------------------------
                // MARK: Telemetry Section
                // ----------------------------------------------------------
                Toggle("Show Telemetry", isOn: $showTelemetry)
                    .foregroundColor(.white)
                    .padding(.horizontal)

                if showTelemetry {
                    DotTestTelemetryView()
                        .padding(.horizontal)
                }
            }
            .padding(.vertical, 20)
        }
        .background(Color.black.opacity(0.88))
    }
}

//
// MARK: UI Helpers
//

private func sectionLabel(_ title: String) -> some View {
    Text(title)
        .font(.headline)
        .foregroundColor(.white)
        .padding(.horizontal)
}

private func tuningSlider(label: String,
                          value: Binding<Double>,
                          range: ClosedRange<Double>) -> some View
{
    VStack(alignment: .leading) {
        Text("\(label): \(value.wrappedValue, specifier: "%.2f")")
            .foregroundColor(.white)
        Slider(value: value, in: range)
    }
    .padding(.horizontal)
}

private func tuningSlider(label: String,
                          value: Binding<CGFloat>,
                          range: ClosedRange<CGFloat>) -> some View
{
    VStack(alignment: .leading) {
        Text("\(label): \(value.wrappedValue, specifier: "%.2f")")
            .foregroundColor(.white)
        Slider(
            value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = CGFloat($0) }
            ),
            in: Double(range.lowerBound)...Double(range.upperBound)
        )
    }
    .padding(.horizontal)
}

private func pickerSection<T: Hashable>(
    title: String,
    selection: Binding<T>,
    items: [T],
    label: @escaping (T) -> Text
) -> some View {
    VStack(alignment: .leading) {
        Text(title)
            .font(.headline)
            .foregroundColor(.white)
        Picker(title, selection: selection) {
            ForEach(items, id: \.self) { item in
                label(item).tag(item)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
    }
    .padding(.horizontal)
}

//
// MARK: Enum Display Extensions
//

extension DotTestMode.Backend {

    static let all: [DotTestMode.Backend] = [
        .cpu,
        .gpuY,
        .gpuCb,
        .gpuReadback
    ]

    var name: String {
        switch self {
        case .cpu:
            return "CPU"

        case .gpuY:
            return "GPU / Y"

        case .gpuCb:
            return "GPU / Cb"

        case .gpuReadback:
            return "GPU / Readback"
        }
    }
}
extension DotTestMode.DebugSurface {
    static let all: [DotTestMode.DebugSurface] = [
        .yRaw, .yNorm, .yEdge,
        .cbRaw, .cbNorm, .cbEdge,
        .fast9y, .fast9cb,
        .mismatchHeatmap,
        .mixedCorners
    ]

    var name: String {
        switch self {
        case .yRaw:            return "Y Raw"
        case .yNorm:           return "Y Norm"
        case .yEdge:           return "Y Edge"
        case .cbRaw:           return "Cb Raw"
        case .cbNorm:          return "Cb Norm"
        case .cbEdge:          return "Cb Edge"
        case .fast9y:          return "FAST9 Y"
        case .fast9cb:         return "FAST9 Cb"
        case .mismatchHeatmap: return "Heatmap"
        case .mixedCorners:    return "Mixed"
        }
    }
}
