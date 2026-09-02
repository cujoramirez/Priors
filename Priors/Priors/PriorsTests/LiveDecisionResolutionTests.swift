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
        // The host app's window can drive this view's render loop, which would
        // advance SKActions between statements -- a villager caught partway
        // through its walk-in, a fading node already collected. Every frame
        // these tests care about is driven explicitly through `update(_:)`, so
        // freeze everything else and keep the assertions deterministic.
        scene.isPaused = true
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

    private typealias Resolution = (
        engaged: Bool,
        zoneDwellSeconds: TimeInterval,
        metrics: (approachFrac: Double, backtracks: Int, idleMs: Int)
    )

    /// Arms a social decision and puts the villager in the state a device
    /// reaches a few seconds later: stopped, phrase showing, waiting. In
    /// production that transition comes from an `SKAction` completion, which
    /// needs a render loop no unit test has -- so without this seam the whole
    /// hold-to-engage / walk-away-to-decline path (11 of every 30 decisions)
    /// is unreachable from a test.
    private func arrivedVillager(in scene: VillageScene) throws -> WaitingVillagerNode {
        let design = ADOSelector.selectDesign(
            posterior: Posterior(), slot: 2, state: SelectionState()
        )
        let decision = LiveDecision(design: design)
        #expect(!decision.isSpatial)
        let location = try #require(scene.decisionLocations.first { $0.trait == .thetaI })
        scene.armDecision(decision, at: location)
        let villager = try #require(armedVillagers(in: scene).first)
        villager.simulateArrivalForTesting()
        #expect(villager.hasArrived)
        return villager
    }

    /// A frame with the player standing still at `point` -- the state the
    /// social branch's hold and idle accounting both care about.
    private func stand(_ scene: VillageScene, at point: CGPoint, at time: TimeInterval) {
        scene.setInputVector(.zero)
        scene.playerNode.position = point
        scene.update(time)
    }

    // MARK: - Spatial: crossing == engage

    @Test func crossingAThresholdResolvesEngagedAndArmsTheNextSlot() async throws {
        let coordinator = makeCoordinator()
        let scene = presentedScene()
        let sampler = MovementSampler()

        var resolutions: [Resolution] = []
        scene.onLiveDecisionResolved = { result in
            resolutions.append(result)
            coordinator.resolveLiveDecision(
                engaged: result.engaged,
                zoneDwellSeconds: result.zoneDwellSeconds,
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

        var resolutions: [Resolution] = []
        scene.onLiveDecisionResolved = { result in
            resolutions.append(result)
            coordinator.resolveLiveDecision(
                engaged: result.engaged,
                zoneDwellSeconds: result.zoneDwellSeconds,
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
        // villager who has not arrived. The repeated `true` does NOT pin
        // `setInteractPressed`'s idempotence here -- with `hasArrived` false
        // the hold branch is unreachable, so nothing would tell the two
        // implementations apart. `repeatedInteractPressesDoNotRestartTheHold`
        // below pins it for real, on an arrived villager.
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

    // MARK: - C1: rt_ms is hesitation in the zone, not the walk to it

    /// SPEC §8.3: `rt_ms` is the "time between entering a threshold's zone and
    /// resolving it". Arming happens the instant the previous decision
    /// resolves, with the player standing wherever that was -- so a timer
    /// started at arm time measures the whole walk across the village. This
    /// pins the semantics: 40 seconds of travel between arming and entering
    /// the zone must not appear in `rt_ms`.
    @Test func rtMsMeasuresTimeInTheZoneNotTimeSinceArming() async throws {
        let coordinator = makeCoordinator()
        let scene = presentedScene()
        let sampler = MovementSampler()

        scene.onLiveDecisionResolved = { result in
            coordinator.resolveLiveDecision(
                engaged: result.engaged,
                zoneDwellSeconds: result.zoneDwellSeconds,
                metrics: result.metrics,
                movementSampler: sampler,
                scene: scene
            )
        }

        coordinator.armNextDecision(scene: scene)
        let threshold = try #require(armedThreshold(in: scene))
        let centre = threshold.position

        // 40 seconds of walking somewhere else entirely, exactly as a player
        // crossing the village (and detouring to deliver a lantern) would.
        for i in 0...40 {
            step(scene, to: offset(centre, dx: 600), at: TimeInterval(i))
        }
        #expect(coordinator.decisions.isEmpty)

        // Then the actual decision: 1.2s from entering the zone to leaving it.
        step(scene, to: offset(centre, dx: 30), at: 41.0)
        step(scene, to: offset(centre, dx: 8), at: 41.6)
        step(scene, to: offset(centre, dx: 400), at: 42.2)

        #expect(coordinator.decisions.count == 1)
        let record = coordinator.decisions[0]
        #expect(record.rtMs == 1_200)
        // The point of the whole fix: the 41s of travel is excluded.
        #expect(record.rtMs < 5_000)
        // SCHEMA §1 -- `rt_ms = t_decided - t_presented`, exactly.
        #expect(abs((record.tDecided - record.tPresented) - Double(record.rtMs) / 1000.0) < 1e-9)
        // And `t_presented` is the zone entry, ~1.2s before the decision, not
        // the arm instant ~42s before it.
        #expect(record.tDecided - record.tPresented < 5.0)
    }

    // MARK: - I6: resolved nodes fade rather than vanishing

    @Test func aResolvedThresholdLeavesTheLiveWorldButFadesOut() async throws {
        let coordinator = makeCoordinator()
        let scene = presentedScene()
        let sampler = MovementSampler()

        scene.onLiveDecisionResolved = { result in
            coordinator.resolveLiveDecision(
                engaged: result.engaged,
                zoneDwellSeconds: result.zoneDwellSeconds,
                metrics: result.metrics,
                movementSampler: sampler,
                scene: scene
            )
        }

        coordinator.armNextDecision(scene: scene)
        let threshold = try #require(armedThreshold(in: scene))
        let centre = threshold.position

        step(scene, to: offset(centre, dx: 400), at: 0.0)
        step(scene, to: offset(centre, dx: 8), at: 0.1)
        step(scene, to: offset(centre, dx: 400), at: 0.2)

        #expect(coordinator.decisions.count == 1)
        // It is out of the live world on the resolving frame -- "exactly one
        // decision is live" stays literally true...
        #expect(!scene.worldNode.children.contains(threshold))
        // ...but it is still on screen, fading, rather than deleted under the
        // player's eyes.
        #expect(threshold.parent != nil)
        #expect(threshold.hasActions())
    }

    // MARK: - I6: a waiting villager never spawns inside geometry

    @Test func aWaitingVillagerWalksInFromWalkableGround() async throws {
        let scene = presentedScene()
        let map = try #require(scene.mapData)
        let design = ADOSelector.selectDesign(
            posterior: Posterior(), slot: 2, state: SelectionState()
        )

        for location in scene.decisionLocations {
            // Sample repeatedly: the approach angle is randomised per arm.
            for _ in 0..<16 {
                let placement = scene.villagerPlacement(for: location.position)
                #expect(map.isWalkable(worldPoint: placement.stand),
                        "villager would wait inside geometry at \(placement.stand)")
                #expect(map.isWalkable(worldPoint: placement.origin),
                        "villager would spawn inside geometry at \(placement.origin)")
                #expect(map.isWalkablePath(from: placement.origin, to: placement.stand),
                        "villager would walk through geometry from \(placement.origin)")
                // Six of the thirty anchors are features rather than floor, so
                // the villager steps aside -- but never further than the zone
                // it is supposed to be standing in.
                let drift = hypot(placement.stand.x - location.position.x,
                                  placement.stand.y - location.position.y)
                #expect(drift <= 96.0)
            }
        }

        // ...and that is in fact where `armDecision` puts it.
        for location in scene.decisionLocations where location.trait == .thetaI {
            scene.armDecision(LiveDecision(design: design), at: location)
            let villager = try #require(armedVillagers(in: scene).first)
            #expect(map.isWalkable(worldPoint: villager.position))
            #expect(map.isWalkablePath(from: villager.position, to: location.position))
        }
    }

    // MARK: - I2: the social path, which no test could reach before

    @Test func holdingInteractAtAnArrivedVillagerEngages() async throws {
        let scene = presentedScene()
        var resolutions: [Resolution] = []
        scene.onLiveDecisionResolved = { resolutions.append($0) }

        let villager = try arrivedVillager(in: scene)
        let beside = CGPoint(x: villager.position.x + 20, y: villager.position.y)

        stand(scene, at: beside, at: 10.0)
        #expect(scene.canInteractNow)
        #expect(resolutions.isEmpty)

        scene.setInteractPressed(true)
        stand(scene, at: beside, at: 10.1)   // hold starts
        stand(scene, at: beside, at: 10.5)   // 0.4s -- not yet
        #expect(resolutions.isEmpty)

        stand(scene, at: beside, at: 10.8)   // 0.7s >= 0.6s
        #expect(resolutions.count == 1)
        #expect(resolutions[0].engaged == true)
        // Hesitation runs from the frame the player entered the zone.
        #expect(abs(resolutions[0].zoneDwellSeconds - 0.8) < 1e-6)
        #expect(armedVillagers(in: scene).isEmpty)
        #expect(scene.canInteractNow == false)
    }

    @Test func walkingAwayFromAnArrivedVillagerDeclines() async throws {
        let scene = presentedScene()
        var resolutions: [Resolution] = []
        scene.onLiveDecisionResolved = { resolutions.append($0) }

        let villager = try arrivedVillager(in: scene)

        // Inside the decline radius (80) but never within the 40pt hold
        // radius -- an approach, then away.
        stand(scene, at: CGPoint(x: villager.position.x + 60, y: villager.position.y), at: 0.0)
        #expect(scene.canInteractNow == false)
        stand(scene, at: CGPoint(x: villager.position.x + 50, y: villager.position.y), at: 0.5)
        #expect(resolutions.isEmpty)

        stand(scene, at: CGPoint(x: villager.position.x + 300, y: villager.position.y), at: 1.5)

        #expect(resolutions.count == 1)
        #expect(resolutions[0].engaged == false)
        #expect(abs(resolutions[0].zoneDwellSeconds - 1.5) < 1e-6)
        // Closest approach was 50pt of the 80pt zone.
        #expect(abs(resolutions[0].metrics.approachFrac - (1.0 - 50.0 / 80.0)) < 0.001)
        #expect(armedVillagers(in: scene).isEmpty)
    }

    @Test func aPartialHoldReleasedEarlyDoesNotEngage() async throws {
        let scene = presentedScene()
        var resolutions: [Resolution] = []
        scene.onLiveDecisionResolved = { resolutions.append($0) }

        let villager = try arrivedVillager(in: scene)
        let beside = CGPoint(x: villager.position.x + 20, y: villager.position.y)

        stand(scene, at: beside, at: 0.0)
        scene.setInteractPressed(true)
        stand(scene, at: beside, at: 0.1)
        stand(scene, at: beside, at: 0.4)    // 0.3s of hold
        scene.setInteractPressed(false)
        stand(scene, at: beside, at: 0.5)
        #expect(resolutions.isEmpty)

        // A second, also-too-short hold does not accumulate with the first.
        scene.setInteractPressed(true)
        stand(scene, at: beside, at: 0.6)
        stand(scene, at: beside, at: 0.9)    // 0.3s again
        scene.setInteractPressed(false)
        stand(scene, at: beside, at: 1.0)

        #expect(resolutions.isEmpty)
        #expect(armedVillagers(in: scene).count == 1)
    }

    /// M6 -- the contract `setInteractPressed` documents, pinned where it is
    /// actually reachable: a re-fired `true` (a per-frame poll, a re-fired
    /// SwiftUI onChange) must not restart the hold timer, or every social
    /// decision would resolve as a decline.
    @Test func repeatedInteractPressesDoNotRestartTheHold() async throws {
        let scene = presentedScene()
        var resolutions: [Resolution] = []
        scene.onLiveDecisionResolved = { resolutions.append($0) }

        let villager = try arrivedVillager(in: scene)
        let beside = CGPoint(x: villager.position.x + 20, y: villager.position.y)

        stand(scene, at: beside, at: 0.0)
        scene.setInteractPressed(true)
        stand(scene, at: beside, at: 0.1)    // hold starts at 0.1
        scene.setInteractPressed(true)       // re-fired press, mid-hold
        scene.setInteractPressed(true)
        stand(scene, at: beside, at: 0.75)   // 0.65s since 0.1

        #expect(resolutions.count == 1, "a re-fired press restarted the hold timer")
        #expect(resolutions[0].engaged == true)
    }

    // MARK: - I3: social idle_ms is stationary time, not elapsed time

    /// SCHEMA §1 defines `idle_ms` as "ms **stationary** inside the scenario
    /// zone." The social branch logged total elapsed time in the zone, so a
    /// player who paced around the villager was logged as idle the whole time.
    @Test func socialIdleMsCountsOnlyStationaryTime() async throws {
        let scene = presentedScene()
        var resolutions: [Resolution] = []
        scene.onLiveDecisionResolved = { resolutions.append($0) }

        let villager = try arrivedVillager(in: scene)
        let near = CGPoint(x: villager.position.x + 60, y: villager.position.y)

        stand(scene, at: near, at: 0.0)                       // enter, standing

        // A second of walking about inside the zone.
        scene.setInputVector(CGVector(dx: 1.0, dy: 0.0))
        scene.playerNode.position = CGPoint(x: near.x + 4, y: near.y)
        scene.update(1.0)

        stand(scene, at: near, at: 2.0)                       // 1s stationary

        stand(scene, at: CGPoint(x: villager.position.x + 300, y: villager.position.y), at: 3.0)

        #expect(resolutions.count == 1)
        let metrics = resolutions[0].metrics
        // 3s in the zone, of which only ~1s was spent standing still.
        #expect(abs(resolutions[0].zoneDwellSeconds - 3.0) < 1e-6)
        #expect(metrics.idleMs >= 900 && metrics.idleMs <= 1_100,
                "idle_ms is stationary time, not elapsed time (got \(metrics.idleMs))")
    }
}
