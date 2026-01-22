//
//  TelemetryDumpBridge.swift
//  LaunchLab
//

import Foundation

@_cdecl("TelemetryDump_dumpCSV")
public func TelemetryDump_dumpCSV() {
    TelemetryDump.dumpCSV()
}
