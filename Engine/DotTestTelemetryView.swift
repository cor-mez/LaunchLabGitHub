//
//  DotTestTelemetryView.swift
//

import SwiftUI

struct DotTestTelemetryView: View {

    @ObservedObject private var mode = DotTestMode.shared
    @State private var expanded = true

    var body: some View {
        VStack(spacing: 12) {

            // Header
            HStack {
                Text("Telemetry")
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Button(action: { expanded.toggle() }) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.white)
                }
            }

            if expanded {
                VStack(alignment: .leading, spacing: 6) {

                    // MARK: – Basic Counts
                    telemetryRow("CPU Corners", "\(mode.cpuCornerCount)")
                    telemetryRow("GPU Corners", "\(mode.gpuCornerCount)")
                    telemetryRow("Matches", "\(mode.matchCorners.count)")
                    telemetryRow("CPU Only", "\(mode.cpuOnlyCorners.count)")
                    telemetryRow("GPU Only", "\(mode.gpuOnlyCorners.count)")

                    // MARK: – Score Statistics
                    telemetryRow("Avg Score", String(format: "%.2f", mode.avgGpuScore))
                    telemetryRow("Min Score", String(format: "%.2f", mode.minGpuScore))
                    telemetryRow("Max Score", String(format: "%.2f", mode.maxGpuScore))

                    // MARK: – Error Metrics
                    telemetryRow("Avg Error", String(format: "%.2f px", mode.avgSpatialError))
                    telemetryRow("Max Error", String(format: "%.2f px", mode.maxSpatialError))

                    // MARK: – NMS
                    telemetryRow("NMS Cluster Size", "\(mode.nmsClusterSize)")

                    // MARK: – Agreement Ratio
                    let ratio = mode.cpuCornerCount > 0
                        ? Float(mode.gpuCornerCount) / Float(mode.cpuCornerCount)
                        : 0
                    telemetryRow("Agreement", String(format: "%.2f", ratio))
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.65))
        .cornerRadius(12)
    }

    // MARK: - UI Helper
    private func telemetryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label + ":")
                .foregroundColor(.white)
            Spacer()
            Text(value)
                .foregroundColor(.white)
        }
    }
}

struct DotTestTelemetryView_Previews: PreviewProvider {
    static var previews: some View {
        DotTestTelemetryView()
            .preferredColorScheme(.dark)
            .padding()
            .background(Color.black)
    }
}
