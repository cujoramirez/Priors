//  Scenarios.swift
//  Scenario templates and session structure. SPEC §3, §4, §4.1, §4.2, §5.1.
//
//  Pure data. Every constant here is quoted from the contract and carries the
//  section it came from. Port of `priors/scenarios.py`.

import Foundation

public enum Trait: String, Codable, Sendable, CaseIterable {
    case thetaE = "theta_e"
    case thetaI = "theta_i"
}

public enum TemplateID: String, Codable, Sendable, CaseIterable {
    case path = "PATH"
    case detour = "DETOUR"
    case error = "ERROR"
    case credit = "CREDIT"
    case give = "GIVE"
    case trade = "TRADE"
}

/// A discretised parameter axis. `isLog` selects geometric spacing.
public struct GridSpec: Sendable, Equatable {
    public let lo: Double
    public let hi: Double
    public let n: Int
    public let isLog: Bool

    public init(lo: Double, hi: Double, n: Int, isLog: Bool = false) {
        self.lo = lo
        self.hi = hi
        self.n = n
        self.isLog = isLog
    }

    /// Matches NumPy's `linspace`/`geomspace` element for element, including
    /// the explicit endpoint assignment. The Python fixtures are the reference,
    /// so the arithmetic has to agree, not merely the intent.
    public func values() -> [Double] {
        guard n > 1 else { return [lo] }
        var out = [Double](repeating: 0, count: n)
        if isLog {
            let a = log10(lo), b = log10(hi)
            let step = (b - a) / Double(n - 1)
            for k in 0..<n { out[k] = pow(10.0, a + Double(k) * step) }
        } else {
            let step = (hi - lo) / Double(n - 1)
            for k in 0..<n { out[k] = lo + Double(k) * step }
        }
        out[0] = lo
        out[n - 1] = hi
        return out
    }
}

public enum Grids {
    /// SPEC §3.1 — θ_e, uniform over [0.05, 0.85], 33 points.
    public static let thetaE = GridSpec(lo: 0.05, hi: 0.85, n: 33)
    /// SPEC §3.2 — θ_i, uniform over [0.02, 0.70], 25 points.
    public static let thetaI = GridSpec(lo: 0.02, hi: 0.70, n: 25)
    /// SPEC §3.3 — β, 2.0–30.0, 15 points, log-spaced.
    public static let beta = GridSpec(lo: 2.0, hi: 30.0, n: 15, isLog: true)

    /// SPEC §3.4 — 33 × 25 × 15 = 12,375 cells.
    public static let cellCount = thetaE.n * thetaI.n * beta.n

    public static func spec(for trait: Trait) -> GridSpec {
        trait == .thetaE ? thetaE : thetaI
    }
}

public struct Template: Sendable {
    public let id: TemplateID
    public let trait: Trait
    public let priceMeans: String
    public let instances: Int
    public let skins: [String]

    /// SPEC §4.1 — a template's price range is its trait's prior support.
    /// No template invents a range of its own.
    public var priceLo: Double { Grids.spec(for: trait).lo }
    public var priceHi: Double { Grids.spec(for: trait).hi }
}

public enum Scenarios {
    public static let templates: [TemplateID: Template] = [
        .path: Template(id: .path, trait: .thetaE, priceMeans: "P(lose 1 lantern)",
                        instances: 12, skins: ["unlit path", "cellar door", "gap in hedge"]),
        .detour: Template(id: .detour, trait: .thetaE, priceMeans: "P(waste 90s)",
                          instances: 4, skins: ["long way round", "closed gate"]),
        .error: Template(id: .error, trait: .thetaI, priceMeans: "cost of going back",
                         instances: 4, skins: ["wrong house", "dropped lantern"]),
        .credit: Template(id: .credit, trait: .thetaI, priceMeans: "size of undeserved reward",
                          instances: 3, skins: ["villager thanks you for another's work"]),
        .give: Template(id: .give, trait: .thetaI, priceMeans: "cost of giving",
                        instances: 4, skins: ["villager needs your lantern"]),
        // SPEC §4.2 — price is P(gamble pays nothing) = 1 − p_win, so the §3.4
        // choice model applies unchanged with no per-template sign flip.
        .trade: Template(id: .trade, trait: .thetaE,
                         priceMeans: "P(gamble pays nothing) = 1 - p_win",
                         instances: 3, skins: ["certain 1 vs p-chance of 3"]),
    ]

    /// Declaration order, used as the last tie-break in design selection.
    public static let templateOrder: [TemplateID] = [.path, .detour, .error, .credit, .give, .trade]

    public static let templatesByTrait: [Trait: [TemplateID]] = [
        .thetaE: [.path, .detour, .trade],
        .thetaI: [.error, .credit, .give],
    ]

    /// SPEC §4 — "Total: 30 decisions."
    public static let decisionCount = 30

    /// SPEC §5.1 — the authored trait sequence. ADO chooses which eligible
    /// template fills each slot and at what price, but never the trait.
    public static let traitSchedule: [Trait] = [
        .thetaE, .thetaE, .thetaI, .thetaE, .thetaE,
        .thetaI, .thetaE, .thetaE, .thetaI, .thetaE,
        .thetaI, .thetaE, .thetaE, .thetaI, .thetaE,
        .thetaE, .thetaI, .thetaE, .thetaE, .thetaI,
        .thetaE, .thetaI, .thetaE, .thetaE, .thetaI,
        .thetaE, .thetaE, .thetaI, .thetaE, .thetaI,
    ]

    /// SPEC §5.2 — 12 candidate prices spanning the valid range.
    public static let priceCandidateCount = 12
    /// SPEC §5.4 — ±0.02 jitter so prices don't look mechanical.
    public static let priceJitter = 0.02
    /// SPEC §5.1 — a template is blocked once the previous two slots both used it.
    public static let curiosityRunLimit = 2

    /// SPEC §4 — PATH #11 re-priced within ±0.03 of PATH #3. These are 1-based
    /// PATH *occurrence* counts, not slot indices.
    public static let repeatTemplate: TemplateID = .path
    public static let repeatSourceInstance = 3
    public static let repeatTargetInstance = 11
    public static let repeatTolerance = 0.03

    /// SPEC §6.1 — once posterior SD for θ_e drops below this, the next PATH is
    /// priced at the posterior mean.
    public static let falsificationSDThreshold = 0.06
    /// SPEC §6.3 — the eye fires once, at a decision index in this closed range.
    public static let eyeDecisionIndexRange = 14...20
    /// SCHEMA §1 — eye_window is true within ±240s of eye_timestamp.
    public static let eyeWindowSeconds = 240.0

    public static func candidatePrices(for trait: Trait,
                                       count: Int = priceCandidateCount) -> [Double] {
        let g = Grids.spec(for: trait)
        return GridSpec(lo: g.lo, hi: g.hi, n: count).values()
    }
}
