//  PosteriorSnapshot.swift
//  SCHEMA §4. Plain values only — safe to serialise straight to JSON.

import Foundation

public struct PosteriorSnapshot: Codable, Sendable, Equatable {
    public let thetaEMean: Double
    public let thetaESD: Double
    public let thetaEGrid: [Double]
    public let thetaEMarginal: [Double]
    public let thetaIMean: Double
    public let thetaISD: Double
    public let thetaIGrid: [Double]
    public let thetaIMarginal: [Double]
    public let betaMean: Double
    public let betaSD: Double

    enum CodingKeys: String, CodingKey {
        case thetaEMean = "theta_e_mean"
        case thetaESD = "theta_e_sd"
        case thetaEGrid = "theta_e_grid"
        case thetaEMarginal = "theta_e_marginal"
        case thetaIMean = "theta_i_mean"
        case thetaISD = "theta_i_sd"
        case thetaIGrid = "theta_i_grid"
        case thetaIMarginal = "theta_i_marginal"
        case betaMean = "beta_mean"
        case betaSD = "beta_sd"
    }

    public func mean(for trait: Trait) -> Double {
        trait == .thetaE ? thetaEMean : thetaIMean
    }

    public func sd(for trait: Trait) -> Double {
        trait == .thetaE ? thetaESD : thetaISD
    }

    /// SPEC §8.1 drives palette and audio decay on mean posterior SD.
    public var meanSD: Double { (thetaESD + thetaISD) / 2.0 }
}
