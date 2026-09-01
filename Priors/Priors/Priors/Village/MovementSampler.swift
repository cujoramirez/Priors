//
//  MovementSampler.swift
//  Priors
//

import Foundation
import PriorsEngine

/// SCHEMA §2 — 4 Hz Movement Sampler during village phase.
@MainActor
public final class MovementSampler {
    public private(set) var samples: [MovementSample] = []
    public private(set) var isSampling: Bool = false

    private let sampleInterval: Duration = .milliseconds(250) // 4 Hz
    private var sessionStart: ContinuousClock.Instant?
    private var samplingTask: Task<Void, Never>?

    private var currentX: Double = 0.0
    private var currentY: Double = 0.0
    private var lastSampledX: Double?
    private var lastSampledY: Double?

    public var regionLookup: ((_ x: Double, _ y: Double) -> String)?

    public init(regionLookup: ((_ x: Double, _ y: Double) -> String)? = nil) {
        self.regionLookup = regionLookup
    }

    /// Start 4 Hz sampling loop.
    public func start(sessionStart: ContinuousClock.Instant = ContinuousClock.now) {
        self.sessionStart = sessionStart
        self.isSampling = true
        self.samples.reserveCapacity(3200)

        samplingTask?.cancel()
        samplingTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled && self.isSampling {
                self.recordSample()
                try? await Task.sleep(for: self.sampleInterval)
            }
        }
    }

    /// Stop sampling loop.
    public func stop() {
        isSampling = false
        samplingTask?.cancel()
        samplingTask = nil
    }

    /// Update player position from game loop.
    public func updatePosition(x: Double, y: Double) {
        self.currentX = x
        self.currentY = y
    }

    /// Manually record a sample (or invoked by the 4 Hz timer loop).
    @discardableResult
    public func recordSample() -> MovementSample {
        let now = ContinuousClock.now
        let start = sessionStart ?? now
        let duration = start.duration(to: now)
        let t = duration.components.seconds.doubleValue + Double(duration.components.attoseconds) / 1e18

        let x = currentX
        let y = currentY

        let isMoving: Bool
        if let lastX = lastSampledX, let lastY = lastSampledY {
            let dist = hypot(x - lastX, y - lastY)
            isMoving = dist > 0.001
        } else {
            isMoving = false
        }

        lastSampledX = x
        lastSampledY = y

        let region: String
        if let lookup = regionLookup {
            region = lookup(x, y)
        } else {
            let gridX = Int(floor(x / 32.0))
            let gridY = Int(floor(y / 32.0))
            region = "r_\(gridX)_\(gridY)"
        }

        let sample = MovementSample(
            t: t,
            x: x,
            y: y,
            moving: isMoving,
            regionID: region
        )
        samples.append(sample)
        return sample
    }

    /// Reset collected samples.
    public func reset() {
        stop()
        samples.removeAll(keepingCapacity: true)
        lastSampledX = nil
        lastSampledY = nil
        sessionStart = nil
    }
}

private extension Int64 {
    var doubleValue: Double {
        Double(self)
    }
}
