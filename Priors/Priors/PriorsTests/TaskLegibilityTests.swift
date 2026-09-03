//
//  TaskLegibilityTests.swift
//  PriorsTests
//
//  SPEC §8.4 — wayfinding and task legibility.
//
//  Before this suite, delivery was silent proximity: no affordance marked a
//  door as needing light, nothing changed on approach, and a player carrying
//  nothing had no way to learn that the well existed. The task the whole
//  village is built around was invisible, and the one visible artefact — a
//  26x26 hard-edged additive square over a delivered door — read as a missing
//  texture rather than as a lit window.
//
//  These pin the fix, and one of them pins something that must NOT be built:
//  see `theInteractButtonIsNeverADeliveryButton`.
//

import Testing
import SpriteKit
import PriorsEngine
@testable import Priors

@Suite("Task legibility")
@MainActor
struct TaskLegibilityTests {

    /// Same presentation dance as `LanternEconomyTests`: the scene's task
    /// state only exists once `didMove(to:)` has built the world.
    private func presentedScene() -> VillageScene {
        let scene = VillageScene(size: CGSize(width: 800, height: 600))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.presentScene(scene)
        scene.isPaused = true
        return scene
    }

    /// Far enough from the well that `updateDeliveries` cannot refill, and far
    /// from every door that nothing delivers. The map is 80x60 tiles; the well
    /// sits at (40, 30).
    private let cornerOfTheMap = CGPoint(x: 4 * 32, y: 4 * 32)

    @Test("Every dark house asks for light")
    func everyDarkHouseAsksForLight() async throws {
        let scene = presentedScene()

        #expect(scene.undeliveredDoors.count > 0)
        #expect(scene.askingWindowCount == scene.undeliveredDoors.count)
        #expect(scene.litWindowCount == 0)
    }

    @Test("Delivering turns an ask into an answer")
    func deliveringTurnsAnAskIntoAnAnswer() async throws {
        let scene = presentedScene()
        let doorsAtStart = scene.undeliveredDoors.count
        let door = try #require(scene.undeliveredDoors.first)

        scene.setCarryAllowance(3)
        scene.setLanternsCarried(3)
        scene.playerNode.position = door
        scene.update(1.0)

        #expect(scene.undeliveredDoors.count == doorsAtStart - 1)
        #expect(!scene.undeliveredDoors.contains(door))
        #expect(scene.askingWindowCount == doorsAtStart - 1)
        #expect(scene.litWindowCount == 1)
    }

    /// The point is continuity. A step change at `deliveryRadius` would make
    /// delivery read as a trigger the player crossed; a smooth ramp makes it
    /// read as somewhere they arrived.
    @Test("The door warms continuously on approach")
    func theDoorWarmsContinuouslyOnApproach() async throws {
        #expect(VillageScene.doorWarmth(distance: 0) > 0.9)
        #expect(VillageScene.doorWarmth(distance: VillageScene.doorWarmthRadius) == 0)
        #expect(VillageScene.doorWarmth(distance: VillageScene.doorWarmthRadius + 40) == 0)

        // Strictly decreasing across the whole approach.
        var previous = VillageScene.doorWarmth(distance: 0)
        for step in 1...60 {
            let d = VillageScene.doorWarmthRadius * CGFloat(step) / 60.0
            let warmth = VillageScene.doorWarmth(distance: d)
            #expect(warmth < previous)
            previous = warmth
        }

        // No discontinuity where delivery happens.
        let justOutside = VillageScene.doorWarmth(distance: VillageScene.deliveryRadius + 0.5)
        let justInside = VillageScene.doorWarmth(distance: VillageScene.deliveryRadius - 0.5)
        #expect(abs(justInside - justOutside) < 0.05)
    }

    @Test("Empty hands are pointed at the well")
    func emptyHandsArePointedAtTheWell() async throws {
        let scene = presentedScene()
        scene.setCarryAllowance(2)
        scene.setLanternsCarried(0)
        scene.playerNode.position = cornerOfTheMap

        scene.update(1.0)
        #expect(scene.wellIndicatorActive)

        // A lantern in hand is its own instruction. The marker goes away.
        scene.setLanternsCarried(1)
        scene.update(2.0)
        #expect(!scene.wellIndicatorActive)
    }

    @Test("Nothing points at the well once every house is lit")
    func nothingPointsAtTheWellOnceEveryHouseIsLit() async throws {
        let scene = presentedScene()
        scene.setCarryAllowance(3)
        scene.setLanternsCarried(3)

        var time = 1.0
        while let door = scene.undeliveredDoors.first {
            scene.setLanternsCarried(3)
            scene.playerNode.position = door
            scene.update(time)
            time += 1.0
        }
        scene.setLanternsCarried(0)
        scene.playerNode.position = cornerOfTheMap
        scene.update(time)

        #expect(scene.undeliveredDoors.isEmpty)
        #expect(!scene.wellIndicatorActive)
    }

    /// The chevron rides an inset ellipse at the screen edge and points the
    /// way the well lies. It cannot be checked by rendering — a camera's
    /// children do not come back through `SKView.texture(from:)` — so its
    /// geometry is checked directly.
    @Test("The well marker points at the well")
    func theWellMarkerPointsAtTheWell() async throws {
        let scene = presentedScene()
        let well = scene.mapData.playerSpawnPosition
        scene.setCarryAllowance(2)
        scene.setLanternsCarried(0)
        // Player to the south-west, so the well lies up and to the right.
        scene.playerNode.position = CGPoint(x: well.x - 300, y: well.y - 260)
        scene.update(1.0)

        let indicator = try #require(scene.wellIndicatorNode)
        #expect(!indicator.isHidden)
        #expect(indicator.alpha > 0.5)

        let expected = atan2(well.y - scene.playerNode.position.y,
                             well.x - scene.playerNode.position.x)
        #expect(abs(indicator.zRotation - expected) < 0.001)
        #expect(indicator.position.x > 0)
        #expect(indicator.position.y > 0)

        // Hands full: the marker is gone, not merely transparent.
        scene.setLanternsCarried(2)
        scene.update(2.0)
        #expect(indicator.isHidden)
    }

    /// SPEC §2.9 — nothing may reward the engaged branch of a measured
    /// template. Delivery lights a window and visibly advances the task; if
    /// the same button did both delivery and `GIVE`, the player would learn
    /// "press Interact = good outcome" and carry that association onto one
    /// side of a measured choice. Delivery therefore stays on proximity, and
    /// Interact stays reserved for armed decisions.
    ///
    /// A future session that wires delivery to the button will fail here.
    @Test("The interact button is never a delivery button")
    func theInteractButtonIsNeverADeliveryButton() async throws {
        let scene = presentedScene()
        let door = try #require(scene.undeliveredDoors.first)

        scene.setCarryAllowance(3)
        scene.setLanternsCarried(3)
        // Beside the door, but outside the delivery radius.
        scene.playerNode.position = CGPoint(x: door.x, y: door.y + VillageScene.deliveryRadius + 20)

        #expect(!scene.canInteractNow)

        scene.setInteractPressed(true)
        scene.update(1.0)

        #expect(scene.lanternsCarried == 3)
        #expect(scene.undeliveredDoors.contains(door))
        #expect(scene.litWindowCount == 0)
    }
}
