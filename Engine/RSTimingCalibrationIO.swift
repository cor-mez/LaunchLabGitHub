//
//  RSTimingCalibrationIO.swift
//  LaunchLab
//

import Foundation

public final class RSTimingCalibrationIO {

    public init() {}

    private var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
        return dir.appendingPathComponent("rs_timing.json")
    }

    public func save(model: RSTimingCalibratedModel) {
        let dict: [String: Any] = [
            "readout": model.readout,
            "curve": model.curve
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

    public func load() -> RSTimingCalibratedModel? {
        guard let data = try? Data(contentsOf: url),
              let o = try? JSONSerialization.jsonObject(with: data),
              let dict = o as? [String: Any],
              let r = dict["readout"] as? Float,
              let c = dict["curve"] as? [Float]
        else { return nil }

        return RSTimingCalibratedModel(readout: r, curve: c)
    }
}