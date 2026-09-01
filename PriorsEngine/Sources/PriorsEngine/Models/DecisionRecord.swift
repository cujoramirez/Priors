//  DecisionRecord.swift
//  SCHEMA §1. One per scenario presented, 30 per session.

import Foundation

public enum EyeSide: String, Codable, Sendable { case before, after }

public struct DecisionRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: Int { index }

    public let index: Int
    public let template: TemplateID
    public let trait: Trait
    public let skin: String
    public let price: Double
    public let engaged: Bool
    public let tPresented: Double
    public let tDecided: Double
    public let rtMs: Int
    public let approachFrac: Double
    public let backtracks: Int
    public let idleMs: Int
    public let eyeWindow: Bool
    public let eyeSide: EyeSide?

    /// Posterior state **before** this decision (SCHEMA §1).
    public let posteriorMeanE: Double
    public let posteriorSDE: Double
    public let posteriorMeanI: Double
    public let posteriorSDI: Double

    /// The model's P(engage) **before** the choice was known.
    ///
    /// SCHEMA §1 is explicit that this is stored before the response. It is
    /// what makes the prediction ledger honest — a value written afterwards
    /// would be a claim about the past rather than a prediction.
    public let predictedEngage: Double

    public let isRepeatOf: Int?
    public let whyText: String?

    public init(
        index: Int, template: TemplateID, trait: Trait, skin: String, price: Double,
        engaged: Bool, tPresented: Double, tDecided: Double, rtMs: Int,
        approachFrac: Double, backtracks: Int, idleMs: Int,
        eyeWindow: Bool, eyeSide: EyeSide?,
        posteriorMeanE: Double, posteriorSDE: Double,
        posteriorMeanI: Double, posteriorSDI: Double,
        predictedEngage: Double, isRepeatOf: Int? = nil, whyText: String? = nil
    ) {
        self.index = index; self.template = template; self.trait = trait
        self.skin = skin; self.price = price; self.engaged = engaged
        self.tPresented = tPresented; self.tDecided = tDecided; self.rtMs = rtMs
        self.approachFrac = approachFrac; self.backtracks = backtracks; self.idleMs = idleMs
        self.eyeWindow = eyeWindow; self.eyeSide = eyeSide
        self.posteriorMeanE = posteriorMeanE; self.posteriorSDE = posteriorSDE
        self.posteriorMeanI = posteriorMeanI; self.posteriorSDI = posteriorSDI
        self.predictedEngage = predictedEngage
        self.isRepeatOf = isRepeatOf; self.whyText = whyText
    }

    enum CodingKeys: String, CodingKey {
        case index, template, trait, skin, price, engaged
        case tPresented = "t_presented"
        case tDecided = "t_decided"
        case rtMs = "rt_ms"
        case approachFrac = "approach_frac"
        case backtracks
        case idleMs = "idle_ms"
        case eyeWindow = "eye_window"
        case eyeSide = "eye_side"
        case posteriorMeanE = "posterior_mean_e"
        case posteriorSDE = "posterior_sd_e"
        case posteriorMeanI = "posterior_mean_i"
        case posteriorSDI = "posterior_sd_i"
        case predictedEngage = "predicted_engage"
        case isRepeatOf = "is_repeat_of"
        case whyText = "why_text"
    }

    /// Seconds spent deciding. Convenience for report copy, which quotes seconds.
    public var rtSeconds: Double { Double(rtMs) / 1000.0 }
}
