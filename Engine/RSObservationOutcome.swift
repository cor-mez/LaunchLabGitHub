//
//  RSObservationOutcome.swift
//  LaunchLab
//
//  Single-frame RS outcome (MANDATORY classification)
//
//  CONTRACT:
//  - Every RS frame MUST end as exactly one of these cases
//  - No third state
//  - No implicit defaults
//  - Authority remains completely uninvolved
//

import Foundation

enum RSObservationOutcome: Equatable {

    /// Frame contains sufficient, localized RS observables
    /// to be logged and analyzed further.
    case observable

    /// Frame is epistemically undecidable under current constraints.
    /// The reason MUST be explicit and canonical.
    case refused(RSRefusalReason)
}

// MARK: - Convenience (NON-AUTHORITATIVE)

extension RSObservationOutcome {

    /// True iff the frame is usable for RS analysis.
    @inline(__always)
    var isObservable: Bool {
        if case .observable = self { return true }
        return false
    }

    /// Extract refusal reason if present.
    @inline(__always)
    var refusalReason: RSRefusalReason? {
        if case .refused(let reason) = self { return reason }
        return nil
    }
}
