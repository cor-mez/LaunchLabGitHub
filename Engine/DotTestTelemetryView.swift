// DotTestTelemetryView.swift

import SwiftUI

struct DotTestTelemetryView: View {

    @ObservedObject private var mode = DotTestMode.shared
    @State private var expanded = true

    var body: some View {
        VStack(spacing: 12) {

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

                    Text("Avg Error: \(mode.avgSpatialError, specifier: "%.2f") px")
                        .foregroundColor(.white)

                    Text("Max Error: \(mode.maxSpatialError, specifier: "%.2f") px")
                        .foregroundColor(.white)

                    Text("NMS Cluster Size: \(mode.nmsClusterSize)")
                        .foregroundColor(.white)
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.6))
        .cornerRadius(12)
    }
}

struct DotTestTelemetryView_Previews: PreviewProvider {
    static var previews: some View {
        DotTestTelemetryView()
            .preferredColorScheme(.dark)
    }
}
