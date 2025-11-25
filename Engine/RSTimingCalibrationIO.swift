//
//  RSTimingCalibrationIO.swift
//  LaunchLab
//

import Foundation

/// Legacy IO for reading/writing RS timing calibration files.
/// Maintains compatibility with the new RSTimingCalibratedModel.
/// Safe to remove once migration is complete.
public final class RSTimingCalibrationIO {

    public init() {}

    private var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
        return dir.appendingPathComponent("rs_timing.json")
    }

    // ---------------------------------------------------------
    // MARK: - SAVE
    // ---------------------------------------------------------
    public func save(model: RSTimingCalibratedModel) {

        // Write using new keys: readout + coeffs
        let dict: [String: Any] = [
            "readout": model.readout,
            "coeffs": model.coeffs
        ]

        if let data = try? JSONSerialization.data(withJSONObject: dict, options: []) {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try? data.write(to: url)
        }
    }

    // ---------------------------------------------------------
    // MARK: - LOAD
    // ---------------------------------------------------------
    public func load() -> RSTimingCalibratedModel? {

        guard let data = try? Data(contentsOf: url),
              let o = try? JSONSerialization.jsonObject(with: data),
              let dict = o as? [String: Any],
              let r = dict["readout"] as? Float,
              let c = dict["coeffs"] as? [Double]
        else { return nil }

        return RSTimingCalibratedModel(coeffs: c, readout: r)
    }
}
