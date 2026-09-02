//
//  VillageContainerView.swift
//  Priors
//
//  SwiftUI container view hosting the SpriteKit VillageScene, the
//  VirtualControls overlay, and in-game chapter story banners. SPEC §8.2/§8.3:
//  there is no modal — decisions are armed in the world and resolve there, so
//  this view only wires input in, overlays non-blocking banners, and resolutions out.
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

    // MARK: - Chapter Story Banners
    @State private var bannerText: String?
    @State private var bannerOpacity: Double = 0.0
    @State private var shownBannerSlots: Set<Int> = []
    @State private var bannerDismissTask: Task<Void, Never>?

    nonisolated public static func bannerMessage(for slot: Int) -> String? {
        switch slot {
        case 0:
            return "Act I: The Evening Bell — The streets are wide, and the lanterns burn bright."
        case 10:
            return "Act II: The Eye in the Frost — Shadows pool at every corner. The frost begins to take the windows."
        case 15:
            return "The Ancient Effigy opens its eyes. You are not alone in the cold."
        case 20:
            return "Act III: The Dying Flame — The bell has gone silent. Only what you carry remains."
        default:
            return nil
        }
    }

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

            // 2. In-Game Chapter Banners Floating Overlay (Top-Center, non-blocking)
            if let text = bannerText {
                VStack {
                    Text(text)
                        .font(.system(size: 14, weight: .medium, design: .serif))
                        .foregroundColor(Color.white.opacity(0.95))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color(red: 16 / 255.0, green: 18 / 255.0, blue: 24 / 255.0).opacity(0.88))
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )
                        )
                        .padding(.top, 16)
                        .padding(.horizontal, 32)
                        .opacity(bannerOpacity)
                        .shadow(color: Color.black.opacity(0.45), radius: 8, x: 0, y: 4)

                    Spacer()
                }
                .allowsHitTesting(false)
                .transition(.opacity)
                .accessibilityIdentifier("chapterBanner")
            }

            // 3. Virtual Controls Overlay
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
            villageScene.setLanternsCarried(coordinator.lanternCount)
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
                checkAndTriggerBanner(for: coordinator.currentSlot)
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
            checkAndTriggerBanner(for: coordinator.currentSlot)

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
                        checkAndTriggerBanner(for: 0)
                    }
                }
            }
        }
        .onDisappear {
            pollTimer?.invalidate()
            pollTimer = nil
            bannerDismissTask?.cancel()
            bannerDismissTask = nil
        }
    }

    private func checkAndTriggerBanner(for slot: Int) {
        guard !shownBannerSlots.contains(slot), let message = Self.bannerMessage(for: slot) else { return }
        shownBannerSlots.insert(slot)
        showBanner(text: message)
    }

    private func showBanner(text: String) {
        bannerDismissTask?.cancel()
        bannerText = text
        withAnimation(.easeIn(duration: 0.8)) {
            bannerOpacity = 1.0
        }
        bannerDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_500_000_000) // 3.5s hold
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.8)) {
                bannerOpacity = 0.0
            }
            try? await Task.sleep(nanoseconds: 800_000_000) // fade out duration
            guard !Task.isCancelled else { return }
            bannerText = nil
        }
    }
}
