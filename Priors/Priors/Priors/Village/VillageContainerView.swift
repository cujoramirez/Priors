//
//  VillageContainerView.swift
//  Priors
//
//  SwiftUI container view hosting the SpriteKit VillageScene and the
//  VirtualControls overlay. SPEC §8.2/§8.3: there is no modal — decisions are
//  armed in the world and resolve there, so this view only wires input in and
//  resolutions out.
//

import SwiftUI
import Observation
import SpriteKit
import PriorsEngine

@MainActor
public struct VillageContainerView: View {
    public var coordinator: VillageCoordinator
    public let movementSampler: MovementSampler
    public let onComplete: @MainActor (SessionRecord) -> Void

    @State private var villageScene: VillageScene
    // `canInteractNow` is a computed property on a plain SKScene subclass that
    // SwiftUI does not observe, so it cannot drive a re-render on its own.
    // Poll it instead — the interact button has to light up as the player
    // walks up to an armed villager, which is a per-frame condition.
    @State private var canInteract: Bool = false
    @State private var pollTimer: Timer?

    public init(
        coordinator: VillageCoordinator,
        movementSampler: MovementSampler,
        onComplete: @escaping @MainActor (SessionRecord) -> Void
    ) {
        self.coordinator = coordinator
        self.movementSampler = movementSampler
        self.onComplete = onComplete

        let scene = VillageScene(size: CGSize(width: 800, height: 450))
        scene.movementSampler = movementSampler
        _villageScene = State(initialValue: scene)
    }

    public var body: some View {
        ZStack {
            // 1. SpriteKit Village Scene
            SpriteView(scene: villageScene)
                .ignoresSafeArea()

            // 2. Virtual Controls Overlay
            VirtualControlsView(
                lanternCount: coordinator.lanternCount,
                canInteract: canInteract,
                onVectorChange: { vector in
                    villageScene.setInputVector(vector)
                },
                onInteractPressChanged: { pressed in
                    villageScene.setInteractPressed(pressed)
                }
            )
        }
        .onAppear {
            movementSampler.start()
            AudioManager.shared.startVillageAudio()
            coordinator.onSessionComplete = { @MainActor record in
                onComplete(record)
            }
            // One tuple parameter, not two: the resolution arrives as a single
            // named tuple (see VillageScene.onLiveDecisionResolved).
            villageScene.onLiveDecisionResolved = { result in
                coordinator.resolveLiveDecision(
                    engaged: result.engaged,
                    zoneDwellSeconds: result.zoneDwellSeconds,
                    metrics: result.metrics,
                    movementSampler: movementSampler,
                    scene: villageScene
                )
            }
            // SPEC §8 — the lantern count is the whole HUD, so the scene's task
            // state has to reach it.
            villageScene.onLanternDelivered = { remaining in
                coordinator.lanternCount = remaining
            }
            villageScene.onLanternsRefilled = { remaining in
                coordinator.lanternCount = remaining
            }
            coordinator.armNextDecision(scene: villageScene)
            // `.onAppear` can run more than once for the same view (a
            // re-entered tab, a recomposed parent). Leaving the previous timer
            // running would double the poll rate every time.
            pollTimer?.invalidate()
            pollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                Task { @MainActor in
                    canInteract = villageScene.canInteractNow
                    // `armNextDecision` needs the scene's playerNode and
                    // decisionLocations, which only exist after
                    // didMove(to:). SwiftUI does not guarantee that SpriteView
                    // has presented the scene by the time .onAppear runs, so
                    // the first arm is retried until it takes. Every later
                    // slot is armed synchronously by resolveLiveDecision, and
                    // this is a no-op once slot 0 is armed (or the session is
                    // over) thanks to armNextDecision's own guards.
                    if coordinator.liveDecision == nil && coordinator.currentSlot == 0 && coordinator.decisions.isEmpty {
                        coordinator.armNextDecision(scene: villageScene)
                    }
                }
            }
        }
        .onDisappear {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }
}
