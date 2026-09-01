//  SessionRecord.swift
//  SCHEMA §2, §3, §5. One SessionRecord per playthrough.

import Foundation

/// SCHEMA §2 — sampled at 4 Hz throughout the village phase.
/// "Cheap. Log wide, interpret narrow."
public struct MovementSample: Codable, Sendable, Equatable {
    public let t: Double
    public let x: Double
    public let y: Double
    public let moving: Bool
    public let regionID: String

    public init(t: Double, x: Double, y: Double, moving: Bool, regionID: String) {
        self.t = t; self.x = x; self.y = y; self.moving = moving; self.regionID = regionID
    }

    enum CodingKeys: String, CodingKey {
        case t, x, y, moving
        case regionID = "region_id"
    }
}

public enum SelfImageLabel: String, Codable, Sendable, CaseIterable {
    case careful = "Careful"
    case curious = "Curious"
    case generous = "Generous"
    case steady = "Steady"

    /// Which trait a temperament claims about the player. Used by SPEC §9.2's
    /// "two claims that match `self_image_label`" ordering rule.
    public var claimedTrait: Trait {
        switch self {
        case .curious: return .thetaE          // claims willingness to explore
        case .generous: return .thetaI         // claims willingness to bear cost
        case .careful: return .thetaE          // claims reluctance to explore
        case .steady: return .thetaI           // claims consistency under cost
        }
    }
}

/// SCHEMA §5 — one per dispute on the argument screen.
public struct ArgumentEvent: Codable, Sendable, Equatable {
    public enum Reason: String, Codable, Sendable {
        case situation, misread, notMe = "not_me"

        /// SPEC §10 — each reason is a different operation on the posterior.
        /// `notMe` holds two hypotheses rather than reweighting, so it has no
        /// single weight.
        public var weight: Double? {
            switch self {
            case .situation: return 0.5
            case .misread: return 0.2
            case .notMe: return nil
            }
        }
    }

    public let claimID: String
    public let reason: Reason
    public let posteriorBefore: PosteriorSnapshot
    public let posteriorAfter: PosteriorSnapshot

    public init(claimID: String, reason: Reason,
                posteriorBefore: PosteriorSnapshot, posteriorAfter: PosteriorSnapshot) {
        self.claimID = claimID; self.reason = reason
        self.posteriorBefore = posteriorBefore; self.posteriorAfter = posteriorAfter
    }

    enum CodingKeys: String, CodingKey {
        case claimID = "claim_id"
        case reason
        case posteriorBefore = "posterior_before"
        case posteriorAfter = "posterior_after"
    }
}

/// SCHEMA §3 — one per playthrough.
public struct SessionRecord: Codable, Sendable {
    public let sessionID: UUID
    public let startedAt: Date

    /// SCHEMA §3 marks this the headline number. SPEC §2.6: the consent screen
    /// was built to be tapped through, and the report says so.
    public let consentDwellMs: Int
    public let consentReadDetails: Bool
    public let detailsDwellMs: Int?

    public let selfImageLabel: SelfImageLabel
    public let selfPredictedThetaE: Double

    /// SPEC §6.3 A/B flag. Half the test cohort runs with the eye off.
    public let eyeEnabled: Bool
    public let eyeTimestamp: Double?
    public let eyeApproachMs: Int
    public let shadowAppearances: [Double]
    public let shadowCorrect: [Bool]

    public var decisions: [DecisionRecord]
    public var movement: [MovementSample]
    public var finalPosterior: PosteriorSnapshot
    public var argumentEvents: [ArgumentEvent]

    public init(
        sessionID: UUID = UUID(), startedAt: Date = Date(),
        consentDwellMs: Int, consentReadDetails: Bool, detailsDwellMs: Int?,
        selfImageLabel: SelfImageLabel, selfPredictedThetaE: Double,
        eyeEnabled: Bool, eyeTimestamp: Double?, eyeApproachMs: Int,
        shadowAppearances: [Double] = [], shadowCorrect: [Bool] = [],
        decisions: [DecisionRecord] = [], movement: [MovementSample] = [],
        finalPosterior: PosteriorSnapshot, argumentEvents: [ArgumentEvent] = []
    ) {
        self.sessionID = sessionID; self.startedAt = startedAt
        self.consentDwellMs = consentDwellMs; self.consentReadDetails = consentReadDetails
        self.detailsDwellMs = detailsDwellMs
        self.selfImageLabel = selfImageLabel; self.selfPredictedThetaE = selfPredictedThetaE
        self.eyeEnabled = eyeEnabled; self.eyeTimestamp = eyeTimestamp
        self.eyeApproachMs = eyeApproachMs
        self.shadowAppearances = shadowAppearances; self.shadowCorrect = shadowCorrect
        self.decisions = decisions; self.movement = movement
        self.finalPosterior = finalPosterior; self.argumentEvents = argumentEvents
    }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case startedAt = "started_at"
        case consentDwellMs = "consent_dwell_ms"
        case consentReadDetails = "consent_read_details"
        case detailsDwellMs = "details_dwell_ms"
        case selfImageLabel = "self_image_label"
        case selfPredictedThetaE = "self_predicted_theta_e"
        case eyeEnabled = "eye_enabled"
        case eyeTimestamp = "eye_timestamp"
        case eyeApproachMs = "eye_approach_ms"
        case shadowAppearances = "shadow_appearances"
        case shadowCorrect = "shadow_correct"
        case decisions, movement
        case finalPosterior = "final_posterior"
        case argumentEvents = "argument_events"
    }

    // MARK: - Derived (SCHEMA §2)

    /// Revisit counts per region, for the pointless-detail claim (SPEC §9.2.4).
    /// Counts *entries* into a region, not samples inside it — standing still
    /// for a minute is one visit, not 240.
    public func revisitCounts() -> [String: Int] {
        var counts: [String: Int] = [:]
        var previous: String?
        for sample in movement.sorted(by: { $0.t < $1.t }) {
            if sample.regionID != previous {
                counts[sample.regionID, default: 0] += 1
                previous = sample.regionID
            }
        }
        return counts
    }

    /// Total seconds spent in regions with no objective. SPEC §8: "Pointless
    /// exploration is the best data in the run."
    public func emptyRegionTime(objectiveRegions: Set<String>) -> Double {
        let sorted = movement.sorted(by: { $0.t < $1.t })
        guard sorted.count > 1 else { return 0 }
        var total = 0.0
        for k in 1..<sorted.count where !objectiveRegions.contains(sorted[k - 1].regionID) {
            total += sorted[k].t - sorted[k - 1].t
        }
        return total
    }
}
