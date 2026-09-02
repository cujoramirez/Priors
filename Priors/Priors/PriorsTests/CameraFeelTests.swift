//
//  CameraFeelTests.swift
//  PriorsTests
//
//  The camera followed the player with a flat per-frame lerp
//  (`position += (target - position) * 0.12`), which converges at whatever
//  rate the display happens to run at: twice as fast on a 120Hz ProMotion
//  device as on a 60Hz one. The same walk across the village was framed
//  differently depending on the hardware. These pin the frame-rate-independent
//  replacement.
//
//  Presentation only. Nothing here touches the decision zones, and the
//  camera's `dt` is deliberately separate from the `currentTime` that
//  SCHEMA §1's timings all read directly.
//

import Testing
import SpriteKit
import PriorsEngine
@testable import Priors

@Suite("Camera feel")
@MainActor
struct CameraFeelTests {

    private func presentedScene() -> VillageScene {
        let scene = VillageScene(size: CGSize(width: 800, height: 600))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.presentScene(scene)
        scene.isPaused = true
        return scene
    }

    /// Drives the player a fixed distance over one simulated second, at two
    /// refresh rates. The camera should end up in materially the same place.
    private func cameraPositionAfterOneSecond(fps: Int) -> CGPoint {
        let scene = presentedScene()
        let start = scene.playerNode.position
        let target = CGPoint(x: start.x + 400, y: start.y)

        // Teleport once, then let the camera chase a stationary target for a
        // simulated second. This isolates the smoothing from the player's own
        // physics, which SpriteKit does not step in a headless test anyway.
        scene.playerNode.position = target

        let frameDuration = 1.0 / Double(fps)
        var t: TimeInterval = 0
        for _ in 0..<fps {
            t += frameDuration
            scene.update(t)
        }
        return scene.sceneCamera.position
    }

    @Test func cameraConvergesAtTheSameRateRegardlessOfRefreshRate() async throws {
        let at60 = cameraPositionAfterOneSecond(fps: 60)
        let at120 = cameraPositionAfterOneSecond(fps: 120)

        // Exponential smoothing makes these agree to within rounding of the
        // per-frame discretisation. The old flat lerp put them roughly a
        // factor of two apart in remaining distance.
        #expect(abs(at60.x - at120.x) < 1.0)
        #expect(abs(at60.y - at120.y) < 1.0)
    }

    /// The village must open already framed on the player. An SKCameraNode
    /// starts at the world origin, so before this the first second of every
    /// session was a swoop in from the bottom-left corner of the map.
    @Test func theCameraStartsFramedOnThePlayer() async throws {
        let scene = presentedScene()
        scene.update(0.0)

        let player = scene.playerNode.position
        let cam = scene.sceneCamera.position
        // Equal up to the map-edge clamping the camera also applies.
        #expect(abs(cam.x - player.x) < 400)
        #expect(abs(cam.y - player.y) < 300)
        #expect(hypot(cam.x, cam.y) > 1.0) // not still sitting at the origin
    }

    /// A stalled frame — a breakpoint, a backgrounded app, a test stepping
    /// `update` by whole seconds — must not snap the camera across the map.
    @Test func aStalledFrameDoesNotSnapTheCamera() async throws {
        let scene = presentedScene()
        scene.update(0.0)
        scene.update(1.0 / 60.0)
        let before = scene.sceneCamera.position

        scene.playerNode.position = CGPoint(x: scene.playerNode.position.x + 600,
                                            y: scene.playerNode.position.y)
        // Ten simulated seconds in a single frame.
        scene.update(10.0)
        let after = scene.sceneCamera.position

        let jump = hypot(after.x - before.x, after.y - before.y)
        // dt is clamped at 0.05s, so one frame can only close ~32% of the gap.
        #expect(jump < 600 * 0.4)
        #expect(jump < 600)
        #expect(jump > 0)
    }
}
