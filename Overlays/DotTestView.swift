// File: Overlays/DotTestView.swift
//
//  DotTestView.swift
//  LaunchLab
//
//  Thin wrapper to present DotTestMode with the shared CameraManager.
//

import SwiftUI

struct DotTestView: View {

    @EnvironmentObject var camera: CameraManager

    var body: some View {
        DotTestMode()
            .environmentObject(camera)
    }
}

struct DotTestView_Previews: PreviewProvider {
    static var previews: some View {
        DotTestView()
            .environmentObject(CameraManager())
    }
}
