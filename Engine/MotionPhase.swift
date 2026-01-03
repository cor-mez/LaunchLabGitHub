//
//  MotionPhase.swift
//  LaunchLab
//
//  Canonical motion authority phases.
//  These are physics-aligned and irreversible.
//

enum MotionPhase {
    case presence     // ball exists, nothing else matters
    case impact       // chaos allowed
    case separation   // ballistic validation only
}
