//  Claim.swift
//  SCHEMA §6, SPEC §9.1.
//
//  Every report line is a Claim. SPEC §2.1: nothing in the report is fictional —
//  every line is a true statement derived from logged data.

import Foundation

/// One claim kind per COPY section. The kind selects the wording; it never
/// supplies a fact.
public enum ClaimKind: String, Codable, Sendable, CaseIterable {
    case opening            // R1
    case confirmLowPrice    // R2
    case confirmQuick       // R3
    case theLine            // R4
    case selfPredictionGap  // R5
    case nearMiss           // R6
    case pointlessDetail    // R7
    case eyeComparison      // R8
    case eyeApproach        // R8b
    case moralLine          // R9
    case temperament        // R10
    case repeatDivergence   // R11
    case consentNumber      // R12
    case gamingBreak        // G1
    case gamingUnknown      // G2
}

public struct Claim: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: ClaimKind

    /// Numeric values, every one traceable to the posterior or the log.
    public let parameters: [String: Double]

    /// String values COPY interpolates that are not numbers — `{landmark}`,
    /// `{error_description}`, `{error_choice}`.
    ///
    /// SCHEMA §6 v1.0 declared `parameters: [String: Double]` only, but COPY R7
    /// and R9 interpolate names and phrases that are not numeric. Kept separate
    /// rather than widened to `Any` so the numeric contract stays exact, and
    /// every value here still comes from the log (a region id, a template's
    /// authored description) — never from a generative model.
    public let stringParameters: [String: String]

    /// Receipts. SPEC §9.1: "never empty".
    public let supportingDecisionIDs: [Int]

    /// Posterior SD at the time of the claim.
    public let confidence: Double

    enum CodingKeys: String, CodingKey {
        case id, kind, parameters, confidence
        case stringParameters = "string_parameters"
        case supportingDecisionIDs = "supporting_decision_ids"
    }

    /// SPEC §9.1 — "A claim with no supporting decisions must not render.
    /// Hard assert."
    ///
    /// The precondition makes an unsupported claim unconstructible, so the
    /// failure surfaces in development rather than in front of a player.
    /// `ClaimGenerator` never trips it: it guards on receipts and omits the
    /// claim instead. Use `Claim.make` where absence is a legitimate outcome.
    public init(
        id: String, kind: ClaimKind,
        parameters: [String: Double] = [:],
        stringParameters: [String: String] = [:],
        supportingDecisionIDs: [Int],
        confidence: Double
    ) {
        precondition(
            !supportingDecisionIDs.isEmpty,
            "Claim '\(id)' has no supporting decisions. SPEC §9.1: every claim carries receipts."
        )
        self.id = id
        self.kind = kind
        self.parameters = parameters
        self.stringParameters = stringParameters
        self.supportingDecisionIDs = supportingDecisionIDs
        self.confidence = confidence
    }

    /// Returns nil rather than trapping when there are no receipts. This is the
    /// constructor the generator uses — a claim the data cannot support is
    /// simply not made.
    public static func make(
        id: String, kind: ClaimKind,
        parameters: [String: Double] = [:],
        stringParameters: [String: String] = [:],
        supportingDecisionIDs: [Int],
        confidence: Double
    ) -> Claim? {
        guard !supportingDecisionIDs.isEmpty else { return nil }
        return Claim(id: id, kind: kind, parameters: parameters,
                     stringParameters: stringParameters,
                     supportingDecisionIDs: supportingDecisionIDs, confidence: confidence)
    }

    /// Decoding cannot go through `init`, so the invariant is enforced here too —
    /// a persisted claim with no receipts must not come back to life.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let ids = try c.decode([Int].self, forKey: .supportingDecisionIDs)
        guard !ids.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .supportingDecisionIDs, in: c,
                debugDescription: "SPEC §9.1: a claim with no supporting decisions must not render."
            )
        }
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(ClaimKind.self, forKey: .kind)
        parameters = try c.decodeIfPresent([String: Double].self, forKey: .parameters) ?? [:]
        stringParameters = try c.decodeIfPresent([String: String].self,
                                                 forKey: .stringParameters) ?? [:]
        supportingDecisionIDs = ids
        confidence = try c.decode(Double.self, forKey: .confidence)
    }
}
