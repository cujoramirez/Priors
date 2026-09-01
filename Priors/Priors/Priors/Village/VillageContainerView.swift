//
//  VillageContainerView.swift
//  Priors
//
//  SwiftUI container view hosting SpriteKit VillageScene, VirtualControls overlay,
//  and ScenarioDialog modal.
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
    @State private var canInteract: Bool = false

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
                onInteract: {
                    if villageScene.activeTrigger != nil {
                        coordinator.presentCurrentScenario(scene: villageScene)
                    }
                }
            )

            // 3. Scenario Presentation Modal
            if coordinator.isPresentingScenario, let prompt = coordinator.activePrompt {
                ScenarioDialogView(
                    prompt: prompt,
                    onChoice: { engaged in
                        let metrics = villageScene.currentScenarioMetrics()
                        coordinator.handleChoice(
                            engaged: engaged,
                            metrics: metrics,
                            movementSampler: movementSampler,
                            scene: villageScene
                        )
                    }
                )
                .transition(.opacity)
            }
        }
        .onAppear {
            movementSampler.start()
            AudioManager.shared.startVillageAudio()
            coordinator.onSessionComplete = { @MainActor record in
                onComplete(record)
            }
            villageScene.onActiveTriggerChanged = { trigger in
                canInteract = (trigger != nil)
            }
            // SPEC §8 — the lantern count is the whole HUD, so the scene's task
            // state has to reach it.
            villageScene.onLanternDelivered = { remaining in
                coordinator.lanternCount = remaining
            }
            villageScene.onLanternsRefilled = { remaining in
                coordinator.lanternCount = remaining
            }
        }
    }
}
