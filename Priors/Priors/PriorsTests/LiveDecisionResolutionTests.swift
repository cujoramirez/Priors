//
//  LiveDecisionResolutionTests.swift
//  PriorsTests
//
//  End-to-end coverage of the scene -> coordinator -> scene arm/resolve chain
//  (SPEC §8.3). VillageCoordinator's own loop test drives
//  `resolveLiveDecision` directly; these tests instead drive the real
//  in-world resolution -- moving `playerNode` across frames and calling
//  `scene.update(_:)` -- so the threshold-crossing logic, the
//  `onLiveDecisionResolved` hop and the re-arm-from-inside-`update()`
//  re-entrancy are all exercised for real.
//

import Testing
import SpriteKit
import PriorsEngine
@testable import Priors

@Suite("Live decision resolution")
@MainActor
struct LiveDecisionResolutionTests {

    // MARK: - Fixtures

    /// `armNextDecision` needs `playerNode` and `decisionLocations`, which only
    /// exist after `didMove(to:)`, so the scene has to be presented.
    private func presentedScene() -> VillageScene {
        let scene = VillageScene(size: CGSize(width: 800, height: 600))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.presentScene(scene)
        return scene
    }

    private func makeCoordinator() -> VillageCoordinator {
        VillageCoordinator(
            consentLog: ConsentLog(),
            selfImageLabel: .curious,
            eyeEnabled: false
        )
    }

    /// One rendered frame at a chosen player position. Input vector is set so
    /// `isMoving`/`currentDirection` are realistic (the zone metrics read
    /// them), but the position is assigned directly: physics does not step in
    /// a headless test, so this is what actually moves the player.
    private func step(_ scene: VillageScene, to point: CGPoint, at time: TimeInterval) {
        scene.setInputVector(CGVector(dx: 1.0, dy: 0.0))
        scene.playerNode.position = point
        scene.update(time)
    }

    private func armedThreshold(in scene: VillageScene) -> ThresholdNode? {
        scene.worldNode.children.compactMap { $0 as? ThresholdNode }.first
    }

    private func armedVillagers(in scene: VillageScene) -> [WaitingVillagerNode] {
        scene.worldNode.children.compactMap { $0 as? WaitingVillagerNode }
    }

    private func offset(_ p: CGPoint, dx: CGFloat) -> CGPoint {
        CGPoint(x: p.x + dx, y: p.y)
    }

    // MARK: - Spatial: crossing == engage

    @Test func crossingAThresholdResolvesEngagedAndArmsTheNextSlot() async throws {
        let coordinator = makeCoordinator()
        let scene = presentedScene()
        let sampler = MovementSampler()

        var resolutions: [(engaged: Bool, metrics: (approachFrac: Double, backtracks: Int, idleMs: Int))] = []
        scene.onLiveDecisionResolved = { result in
            resolutions.append(result)
            coordinator.resolveLiveDecision(
                engaged: result.engaged,
                metrics: result.metrics,
                movementSampler: sampler,
                scene: scene
            )
        }

        coordinator.armNextDecision(scene: scene)

        // Slot 0 is a theta_e slot, and every theta_e template is spatial.
        let armed = try #require(coordinator.liveDecision)
        #expect(armed.isSpatial)
        let threshold = try #require(armedThreshold(in: scene))
        let centre = threshold.position

        // Far outside: nothing happens.
        step(scene, to: offset(centre, dx: 400), at: 0.0)
        #expect(resolutions.isEmpty)
        #expect(coordinator.currentSlot == 0)

        // Inside `radius` (36) but not yet committed.
        step(scene, to: offset(centre, dx: 30), at: 0.1)
        #expect(resolutions.isEmpty)

        // Inside `commitRadius` (14) -- this is the crossing.
        step(scene, to: offset(centre, dx: 8), at: 0.2)
        #expect(resolutions.isEmpty, "resolution happens on leaving, not on arrival")

        // Leaving the zone resolves it.
        step(scene, to: offset(centre, dx: 400), at: 0.3)

        #expect(resolutions.count == 1)
        #expect(resolutions.first?.engaged == true)
        // Got to 8pt of a 36pt zone, so approachFrac is 1 - 8/36.
        let approach = try #require(resolutions.first?.metrics.approachFrac)
        #expect(abs(approach - (1.0 - 8.0 / 36.0)) < 0.001)

        // The coordinator logged it and armed the next slot from inside
        // `scene.update(_:)` -- the re-entrant path.
        #expect(coordinator.currentSlot == 1)
        #expect(coordinator.decisions.count == 1)
        #expect(coordinator.decisions[0].engaged == true)
        #expect(coordinator.decisions[0].price == armed.design.price)
        #expect(coordinator.liveDecision != nil)
        #expect(coordinator.liveDecision?.design.slot == 1)

        // Exactly one decision is live: the old threshold is gone and exactly
        // one new node stands in its place.
        let next = try #require(armedThreshold(in: scene))
        #expect(next !== threshold)
        #expect(scene.worldNode.children.compactMap { $0 as? ThresholdNode }.count == 1)
        #expect(armedVillagers(in: scene).isEmpty)

        // And it fires exactly once: idling far from the new threshold adds
        // no further resolutions.
        for i in 4...12 {
            step(scene, to: offset(next.position, dx: 600), at: TimeInterval(i) * 0.1)
        }
        #expect(resolutions.count == 1)
        #expect(coordinator.currentSlot == 1)
    }

    // MARK: - Spatial: approach then leave == decline

    @Test func approachingWithoutCommittingResolvesDeclined() async throws {
        let coordinator = makeCoordinator()
        let scene = presentedScene()
        let sampler = MovementSampler()

        var resolutions: [(engaged: Bool, metrics: (approachFrac: Double, backtracks: Int, idleMs: Int))] = []
        scene.onLiveDecisionResolved = { result in
            resolutions.append(result)
            coordinator.resolveLiveDecision(
                engaged: result.engaged,
                metrics: result.metrics,
                movementSampler: sampler,
                scene: scene
            )
        }

        coordinator.armNextDecision(scene: scene)
        let threshold = try #require(armedThreshold(in: scene))
        let centre = threshold.position

        step(scene, to: offset(centre, dx: 400), at: 0.0)
        // Enter the 36pt zone but never get inside the 14pt commit radius.
        step(scene, to: offset(centre, dx: 32), at: 0.1)
        step(scene, to: offset(centre, dx: 22), at: 0.2)
        step(scene, to: offset(centre, dx: 28), at: 0.3)
        #expect(resolutions.isEmpty)

        step(scene, to: offset(centre, dx: 400), at: 0.4)

        #expect(resolutions.count == 1)
        #expect(resolutions.first?.engaged == false)
        // Closest approach was 22pt of 36, so approachFrac reflects a real
        // partial approach rather than 0 or 1.
        let approach = try #require(resolutions.first?.metrics.approachFrac)
        #expect(abs(approach - (1.0 - 22.0 / 36.0)) < 0.001)
        #expect(approach > 0.0 && approach < 1.0)

        #expect(coordinator.currentSlot == 1)
        #expect(coordinator.decisions.count == 1)
        #expect(coordinator.decisions[0].engaged == false)
        #expect(coordinator.liveDecision != nil)
    }

    // MARK: - Passing through without entering resolves nothing

    @Test func stayingOutsideTheZoneNeverResolves() async throws {
        let coordinator = makeCoordinator()
        let scene = presentedScene()

        var resolutions = 0
        scene.onLiveDecisionResolved = { _ in resolutions += 1 }

        coordinator.armNextDecision(scene: scene)
        let threshold = try #require(armedThreshold(in: scene))

        // Skirt the zone: 40pt away is outside the 36pt radius.
        for i in 0...20 {
            step(scene, to: offset(threshold.position, dx: 40 + CGFloat(i)), at: TimeInterval(i) * 0.1)
        }

        #expect(resolutions == 0)
        #expect(coordinator.currentSlot == 0)
        #expect(coordinator.decisions.isEmpty)
    }

    // MARK: - Social: interact is gated on arrival, and press is idempotent

    @Test func socialDecisionIgnoresInteractUntilTheVillagerHasArrived() async throws {
        let scene = presentedScene()

        var resolutions = 0
        scene.onLiveDecisionResolved = { _ in resolutions += 1 }

        // Slot 2 is the first theta_i slot, so its design is social.
        let design = ADOSelector.selectDesign(
            posterior: Posterior(),
            slot: 2,
            state: SelectionState()
        )
        let social = LiveDecision(design: design)
        #expect(!social.isSpatial)

        let location = try #require(scene.decisionLocations.first { $0.trait == .thetaI })
        scene.armDecision(social, at: location)

        // A WaitingVillagerNode is placed, and no threshold survives.
        #expect(armedVillagers(in: scene).count == 1)
        #expect(armedThreshold(in: scene) == nil)

        // `walkIn` sets `hasArrived` from an SKAction completion, which a
        // headless test cannot advance, so the villager is permanently
        // mid-approach here. That is exactly the state the gate exists for:
        // interact must stay disabled and nothing may resolve.
        #expect(scene.canInteractNow == false)
        scene.playerNode.position = location.position
        scene.update(0.0)
        #expect(scene.canInteractNow == false)

        // Holding Interact through the full hold duration must not resolve a
        // villager who has not arrived. The repeated `true` also pins
        // `setInteractPressed`'s idempotence contract: a re-fired press must
        // not restart or latch the hold timer.
        scene.setInteractPressed(true)
        scene.setInteractPressed(true)
        for i in 1...40 {
            scene.update(TimeInterval(i) * 0.1)
        }
        #expect(resolutions == 0)

        scene.setInteractPressed(false)
        scene.setInteractPressed(false)
        scene.update(5.0)
        #expect(resolutions == 0)
        #expect(armedVillagers(in: scene).count == 1)
    }

    // MARK: - Arming replaces whatever was live

    @Test func armingASecondDecisionRemovesTheFirst() async throws {
        let scene = presentedScene()

        let spatialDesign = ADOSelector.selectDesign(
            posterior: Posterior(), slot: 0, state: SelectionState()
        )
        let socialDesign = ADOSelector.selectDesign(
            posterior: Posterior(), slot: 2, state: SelectionState()
        )

        let spatialLocation = try #require(scene.decisionLocations.first { $0.trait == .thetaE })
        let socialLocation = try #require(scene.decisionLocations.first { $0.trait == .thetaI })

        scene.armDecision(LiveDecision(design: spatialDesign), at: spatialLocation)
        #expect(armedThreshold(in: scene) != nil)
        #expect(armedVillagers(in: scene).isEmpty)

        scene.armDecision(LiveDecision(design: socialDesign), at: socialLocation)
        #expect(armedThreshold(in: scene) == nil, "the previous threshold must be removed")
        #expect(armedVillagers(in: scene).count == 1)
    }
}
