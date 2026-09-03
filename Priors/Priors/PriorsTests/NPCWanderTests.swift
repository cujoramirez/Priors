//
//  NPCWanderTests.swift
//  PriorsTests
//
//  Bug B — wandering villagers teleported. Two defects compounded:
//
//  1. `startWanderBehavior` built ONE `SKAction.wait(forDuration:)` from a
//     random draw and handed it to `repeatForever`. The draw happens when the
//     action is constructed, so every NPC kept a single fixed cadence for the
//     whole session.
//  2. The repeat loop did not wait for the walk. `wanderToRandomNearbyPoint`
//     ended in an UNKEYED `run(.sequence([move, endAction]))`, and with
//     `wanderRadius` 60 a walk lasts up to ~3.4s (`dist / 35`) while an NPC
//     that drew a 2.0s wait starts the next one. Two concurrent `move(to:)`
//     actions each interpolate from their own start position and both write
//     `position` every frame. That fight is the teleport.
//

import Testing
import SpriteKit
@testable import Priors

@Suite("NPC wandering")
@MainActor
struct NPCWanderTests {

    private func npc() -> NPCNode {
        NPCNode(id: "test", position: CGPoint(x: 500, y: 500), wanderRadius: 60)
    }

    /// The invariant that matters: however many times a wander is triggered,
    /// the node is never running two movements at once. Every action it runs
    /// must be one of the three it owns by key — so removing those three must
    /// leave nothing behind. An unkeyed movement would survive and fail here.
    @Test("A second wander never leaves two movements running")
    func aSecondWanderNeverLeavesTwoMovementsRunning() async throws {
        let villager = npc()

        villager.wanderToRandomNearbyPoint()
        #expect(villager.action(forKey: NPCNode.moveActionKey) != nil)

        villager.wanderToRandomNearbyPoint()
        #expect(villager.action(forKey: NPCNode.moveActionKey) != nil)

        villager.removeAction(forKey: NPCNode.moveActionKey)
        villager.removeAction(forKey: NPCNode.walkActionKey)
        villager.removeAction(forKey: NPCNode.wanderScheduleKey)
        #expect(!villager.hasActions())
    }

    /// The cadence has to be drawn fresh for each cycle. A `wait` built once
    /// and repeated forever draws its duration once and keeps it.
    @Test("Each wander interval is drawn fresh")
    func eachWanderIntervalIsDrawnFresh() async throws {
        let villager = npc()
        var durations: Set<TimeInterval> = []

        for _ in 0..<30 {
            villager.scheduleNextWander()
            let scheduled = try #require(villager.action(forKey: NPCNode.wanderScheduleKey))
            durations.insert(scheduled.duration)
        }

        #expect(durations.count > 1)
        #expect(durations.allSatisfy { $0 >= NPCNode.wanderInterval.lowerBound
                                    && $0 <= NPCNode.wanderInterval.upperBound })
    }

    /// A villager that is walking is scheduled to wander again only by the
    /// walk's own completion, so the schedule cannot outrun the movement.
    @Test("A walking villager has no wander scheduled behind it")
    func aWalkingVillagerHasNoWanderScheduledBehindIt() async throws {
        let villager = npc()

        villager.wanderToRandomNearbyPoint()

        #expect(villager.action(forKey: NPCNode.wanderScheduleKey) == nil)
        #expect(villager.action(forKey: NPCNode.moveActionKey) != nil)
    }
}
