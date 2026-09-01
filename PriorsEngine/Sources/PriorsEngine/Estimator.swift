//  Estimator.swift
//  Core ML wrapper. SCHEMA §8.
//
//  SPEC §2.8 is the governing rule: "Core ML never decides what to say.
//  Foundation Models never decides what is true. The Bayesian posterior is the
//  sole source of claims."
//
//  So this type produces no claims and exposes no opinion to the player. It
//  offers fast intuition and continuous-feature handling, and when it disagrees
//  with the grid posterior by more than 2 SD, SCHEMA §8 says to log the
//  disagreement and not surface it in v1. `disagreements` is that log.
//
//  The estimator is also the most brittle component in the system: the research
//  repo found it will happily learn the synthetic generator's behavioural
//  formula instead of the task unless trained with channel augmentation. That is
//  another reason it is kept away from anything a player reads.

import Foundation
#if canImport(CoreML)
@preconcurrency import CoreML
#endif

/// SCHEMA §8 input layout. The order is the contract — a silent mismatch
/// between this and `priors/features.py` would be invisible until the app was
/// wrong, so both sides name the channels explicitly.
public enum EstimatorFeature: Int, CaseIterable, Sendable {
    case price, engaged, logRTMs, approachFrac, backtracks, logIdleMs
    case templateOneHotE, templateOneHotI, eyeWindow

    public static let count = EstimatorFeature.allCases.count   // 9
}

public struct EstimatorOutput: Sendable, Equatable {
    public let thetaEHat: Double
    public let thetaIHat: Double
    public let logBetaHat: Double
    public let uncertaintyHat: Double

    public var betaHat: Double { exp(logBetaHat) }
}

/// Injectable so the engine can be tested without a compiled model present.
public protocol EstimatorBackend: Sendable {
    func predict(features: [Float]) throws -> EstimatorOutput
}

public struct EstimatorDisagreement: Sendable, Equatable {
    public let gridMean: Double
    public let gridSD: Double
    public let estimate: Double
    public let sigmas: Double
}

public final class Estimator: @unchecked Sendable {
    public static let inputRows = Scenarios.decisionCount      // 30
    public static let inputColumns = EstimatorFeature.count    // 9

    private let backend: EstimatorBackend?
    private let lock = NSLock()
    private var _disagreements: [EstimatorDisagreement] = []

    /// Disagreements with the grid posterior beyond 2 SD. Logged, never shown.
    public var disagreements: [EstimatorDisagreement] {
        lock.lock(); defer { lock.unlock() }
        return _disagreements
    }

    public init(backend: EstimatorBackend?) {
        self.backend = backend
    }

    /// True when a model is loaded. The app must behave identically either way:
    /// nothing a player sees depends on this.
    public var isAvailable: Bool { backend != nil }

    /// SCHEMA §8 — `[30, 9]` float array, zero-padded. Padded rows are all-zero,
    /// which is how the network's mask detects them.
    public static func buildFeatures(from decisions: [DecisionRecord]) -> [Float] {
        var out = [Float](repeating: 0, count: inputRows * inputColumns)
        for d in decisions.sorted(by: { $0.index < $1.index }).prefix(inputRows) {
            let row = d.index * inputColumns
            out[row + EstimatorFeature.price.rawValue] = Float(d.price)
            out[row + EstimatorFeature.engaged.rawValue] = d.engaged ? 1 : 0
            out[row + EstimatorFeature.logRTMs.rawValue] = Float(log(max(Double(d.rtMs), 1)))
            out[row + EstimatorFeature.approachFrac.rawValue] = Float(d.approachFrac)
            out[row + EstimatorFeature.backtracks.rawValue] = Float(d.backtracks)
            out[row + EstimatorFeature.logIdleMs.rawValue] = Float(log(Double(d.idleMs) + 1))
            out[row + EstimatorFeature.templateOneHotE.rawValue] = d.trait == .thetaE ? 1 : 0
            out[row + EstimatorFeature.templateOneHotI.rawValue] = d.trait == .thetaI ? 1 : 0
            out[row + EstimatorFeature.eyeWindow.rawValue] = d.eyeWindow ? 1 : 0
        }
        return out
    }

    /// Run the estimator and record any disagreement with the grid posterior.
    /// Returns nil when no model is loaded — callers must treat that as normal.
    @discardableResult
    public func estimate(decisions: [DecisionRecord],
                         comparedTo posterior: PosteriorSnapshot) -> EstimatorOutput? {
        guard let backend else { return nil }
        guard let out = try? backend.predict(features: Self.buildFeatures(from: decisions)) else {
            return nil
        }

        // SCHEMA §8 — "If it disagrees with the grid posterior by more than
        // 2 SD, log the disagreement — do not surface it in v1."
        if posterior.thetaESD > 0 {
            let sigmas = abs(out.thetaEHat - posterior.thetaEMean) / posterior.thetaESD
            if sigmas > 2.0 {
                lock.lock()
                _disagreements.append(EstimatorDisagreement(
                    gridMean: posterior.thetaEMean, gridSD: posterior.thetaESD,
                    estimate: out.thetaEHat, sigmas: sigmas))
                lock.unlock()
            }
        }
        return out
    }
}

#if canImport(CoreML)
/// Loads `PriorsEstimator.mlpackage`. Absent model is not an error — the app
/// runs identically without it (SPEC §2.8).
/// `MLModel.prediction` is documented as thread-safe, so the unchecked
/// conformance is a statement about CoreML's contract rather than a bypass.
public final class CoreMLBackend: EstimatorBackend, @unchecked Sendable {
    private let model: MLModel

    public init?(bundle: Bundle = .main, resource: String = "PriorsEstimator") {
        guard let url = bundle.url(forResource: resource, withExtension: "mlmodelc")
                ?? bundle.url(forResource: resource, withExtension: "mlpackage"),
              let model = try? MLModel(contentsOf: url)
        else { return nil }
        self.model = model
    }

    public func predict(features: [Float]) throws -> EstimatorOutput {
        let shape: [NSNumber] = [1,
                                 NSNumber(value: Estimator.inputRows),
                                 NSNumber(value: Estimator.inputColumns)]
        let array = try MLMultiArray(shape: shape, dataType: .float32)
        let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: features.count)
        for (i, v) in features.enumerated() { ptr[i] = v }

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "decisions": MLFeatureValue(multiArray: array)
        ])
        let result = try model.prediction(from: input)
        guard let traits = result.featureValue(for: "traits")?.multiArrayValue,
              traits.count >= 4
        else { throw EstimatorError.unexpectedOutput }

        return EstimatorOutput(
            thetaEHat: traits[0].doubleValue,
            thetaIHat: traits[1].doubleValue,
            logBetaHat: traits[2].doubleValue,
            uncertaintyHat: traits[3].doubleValue
        )
    }
}
#endif

public enum EstimatorError: Error { case unexpectedOutput }
