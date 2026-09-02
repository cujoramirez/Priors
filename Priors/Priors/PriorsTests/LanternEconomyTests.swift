//
//  LanternEconomyTests.swift
//  PriorsTests
//
//  SPEC §4 — the lantern count is the only stake the templates have. PATH's
//  price is P(lose 1 lantern), GIVE's is the cost of giving one away, TRADE's
//  is the variance of a gamble over them. That only means anything if a loss
//  survives the next trip past the well.
//
//  Before this suite, `updateDeliveries` refilled to a flat `carryCapacity`
//  whenever the Runner was carrying fewer than three, so every decision-driven
//  loss was refunded on the next refill and the prices had no textural stake
//  behind them at all. These pin the fix.
//

import Testing
import SpriteKit
import PriorsEngine
@testable import Priors

@Suite("Lantern economy")
@MainActor
struct LanternEconomyTests {

    /// `updateDeliveries` needs `playerNode` and `mapData`, which only exist
    /// after `didMove(to:)`. The player spawns at the well, so a single
    /// `update(_:)` at the spawn position is a refill attempt.
    private func presentedScene() -> VillageScene {
        let scene = VillageScene(size: CGSize(width: 800, height: 600))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.presentScene(scene)
        scene.isPaused = true
        return scene
    }

    @Test func wellRefillsToTheAllowanceNotTheCapacity() async throws {
        let scene = presentedScene()
        // One lantern was lost to a decision: the allowance drops with it.
        scene.setCarryAllowance(2)
        scene.setLanternsCarried(0)

        scene.update(1.0)

        #expect(scene.lanternsCarried == 2)
        #expect(scene.lanternsCarried != VillageScene.carryCapacity)
    }

    @Test func wellGivesNothingOnceTheAllowanceIsSpent() async throws {
        let scene = presentedScene()
        scene.setCarryAllowance(0)
        scene.setLanternsCarried(0)

        scene.update(1.0)

        #expect(scene.lanternsCarried == 0)
    }

    @Test func allowanceIsClampedToTheCarryCapacity() async throws {
        let scene = presentedScene()

        scene.setCarryAllowance(9)
        #expect(scene.carryAllowance == VillageScene.carryCapacity)

        scene.setCarryAllowance(-2)
        #expect(scene.carryAllowance == 0)
    }

    /// The whole point of the change: a loss is not refunded. Full allowance,
    /// empty hands, refill — three. Then a loss, refill again — two, not three.
    @Test func aLostLanternStaysLostAcrossRefills() async throws {
        let scene = presentedScene()

        scene.setCarryAllowance(VillageScene.carryCapacity)
        scene.setLanternsCarried(0)
        scene.update(1.0)
        #expect(scene.lanternsCarried == VillageScene.carryCapacity)

        // A GIVE resolves: one lantern gone, and the allowance goes with it.
        scene.setCarryAllowance(VillageScene.carryCapacity - 1)
        scene.setLanternsCarried(VillageScene.carryCapacity - 1)

        scene.update(2.0)
        #expect(scene.lanternsCarried == VillageScene.carryCapacity - 1)
    }

    /// SPEC §4.2's TRADE pays three where one was certain. The old
    /// `lanternCount += 2` assumed the Runner held exactly one and could
    /// otherwise put the HUD above the number of lanterns that fit.
    @Test func lanternCountNeverExceedsCapacityAcrossAFullSession() async throws {
        let consent = ConsentLog()
        consent.consentDwellMs = 2400
        consent.consentReadDetails = true

        let coordinator = VillageCoordinator(
            consentLog: consent,
            selfImageLabel: .curious,
            eyeEnabled: false
        )
        let scene = presentedScene()
        let sampler = MovementSampler()

        #expect(coordinator.lanternCount == 3)
        #expect(coordinator.carryAllowance == VillageScene.carryCapacity)

        coordinator.armNextDecision(scene: scene)

        // Engage everything — the branch that can gain lanterns — for 30 slots.
        var guardCounter = 0
        while coordinator.currentSlot < Scenarios.decisionCount, guardCounter < 60 {
            guardCounter += 1
            coordinator.resolveLiveDecision(
                engaged: true,
                zoneDwellSeconds: 1.2,
                metrics: (approachFrac: 0.5, backtracks: 0, idleMs: 100),
                movementSampler: sampler,
                scene: scene
            )
            #expect(coordinator.lanternCount <= VillageScene.carryCapacity)
            #expect(coordinator.lanternCount >= 0)
            #expect(coordinator.carryAllowance <= VillageScene.carryCapacity)
            #expect(coordinator.carryAllowance >= 0)
            // The scene is never told it may hold more than the allowance.
            #expect(scene.carryAllowance <= VillageScene.carryCapacity)
        }

        #expect(coordinator.currentSlot == Scenarios.decisionCount)
    }

    /// The allowance is a ratchet: it only ever falls, never recovers past
    /// where the run's losses left it. (Gains are clamped by the capacity, so
    /// a TRADE win cannot buy back the ceiling a GIVE gave up.)
    @Test func theAllowanceNeverClimbsBackAboveCapacity() async throws {
        let consent = ConsentLog()
        consent.consentDwellMs = 2400
        consent.consentReadDetails = true

        let coordinator = VillageCoordinator(
            consentLog: consent,
            selfImageLabel: .curious,
            eyeEnabled: false
        )
        let scene = presentedScene()
        let sampler = MovementSampler()

        coordinator.armNextDecision(scene: scene)

        var highWaterMark = coordinator.carryAllowance
        var guardCounter = 0
        while coordinator.currentSlot < Scenarios.decisionCount, guardCounter < 60 {
            guardCounter += 1
            coordinator.resolveLiveDecision(
                engaged: true,
                zoneDwellSeconds: 1.2,
                metrics: (approachFrac: 0.5, backtracks: 0, idleMs: 100),
                movementSampler: sampler,
                scene: scene
            )
            highWaterMark = max(highWaterMark, coordinator.carryAllowance)
        }

        #expect(highWaterMark == VillageScene.carryCapacity)
    }
}
