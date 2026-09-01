//
//  VillageScene.swift
//  Priors
//
//  Main SpriteKit scene for the top-down village, managing camera, player physics,
//  4 Hz movement sampling, palette decay filter, predictive shadow, and the eye.
//

import SpriteKit
import GameplayKit
import UIKit
import PriorsEngine

@MainActor
public class VillageScene: SKScene, SKPhysicsContactDelegate {
    // Root Effect Node for continuous palette decay (SPEC §8.1)
    public private(set) var worldEffectNode: SKEffectNode!
    public private(set) var worldNode: SKNode!

    // Entities
    public private(set) var playerNode: PlayerNode!
    public private(set) var npcs: [NPCNode] = []
    public private(set) var eyeNode: EyeNode!
    public private(set) var triggers: [ScenarioTriggerNode] = []
    public private(set) var mapData: VillageMapData!

    // Camera & Lighting
    public private(set) var sceneCamera: SKCameraNode!
    public private(set) var lightingOverlay: SKSpriteNode!

    // Controls and Movement
    private var inputVector: CGVector = .zero
    public var movementSampler: MovementSampler?
    private var lastSampleTime: TimeInterval = 0.0

    // Scenario Trigger Proximity Tracking
    public private(set) var activeTrigger: ScenarioTriggerNode?
    public var onActiveTriggerChanged: ((ScenarioTriggerNode?) -> Void)?

    // MARK: - The task (SPEC §8)
    //
    // "Task: deliver lanterns to houses before dark." It is the cover story for
    // the 30 decisions, not a game to win: SPEC §2.4 forbids a score and a fail
    // state, so nothing is counted, nothing is timed and nothing is lost by
    // ignoring it. Delivery happens on proximity rather than on the interact
    // button, which stays reserved for scenarios.
    //
    // Progress is shown only by the windows lighting up. SPEC §8 restricts the
    // HUD to the lantern count, so there is no checklist and no marker.
    private var undeliveredDoors: [CGPoint] = []
    private var litWindows: [CGPoint: SKNode] = [:]
    public var onLanternDelivered: ((Int) -> Void)?
    public var onLanternsRefilled: ((Int) -> Void)?
    public private(set) var lanternsCarried: Int = 3
    private static let carryCapacity = 3
    private static let deliveryRadius: CGFloat = 40
    private static let refillRadius: CGFloat = 56

    // Zone Exploration Metrics (SCHEMA §1, §7.1)
    private var zoneEntryTime: TimeInterval = 0.0
    private var zoneLastMovementTime: TimeInterval = 0.0
    private var zoneIdleDuration: TimeInterval = 0.0
    private var zoneMinDistance: CGFloat = 1000.0
    private var zoneBacktrackCount: Int = 0
    private var zonePreviousDirection: Direction?

    // Eye Tracking Metrics (SPEC §6.3, SCHEMA §3)
    private var eyeFlashedTime: TimeInterval?
    public private(set) var eyeApproachDurationMs: Int = 0
    private var isNearEye: Bool = false
    private var nearEyeEntryTime: TimeInterval = 0.0

    // Palette decay
    private let paletteController = PaletteController()

    public override init(size: CGSize) {
        super.init(size: size)
        self.scaleMode = .resizeFill
        self.backgroundColor = .black
        setupWorld()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.scaleMode = .resizeFill
        self.backgroundColor = .black
        setupWorld()
    }

    public override func didMove(to view: SKView) {
        if worldNode == nil {
            setupWorld()
        }
    }

    private func setupWorld() {
        guard worldNode == nil else { return }

        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self

        // 1. World Effect Node (Dusk shift)
        worldEffectNode = SKEffectNode()
        worldEffectNode.shouldRasterize = false
        addChild(worldEffectNode)

        worldNode = SKNode()
        worldEffectNode.addChild(worldNode)

        // 2. Build 80x60 Village Tilemap
        let buildResult = VillageMapBuilder.shared.buildVillage(in: worldNode)
        self.mapData = buildResult.mapData
        self.undeliveredDoors = buildResult.mapData.doorPositions
        self.triggers = buildResult.triggers
        self.eyeNode = buildResult.eyeNode

        // 3. Player Node
        playerNode = PlayerNode()
        playerNode.position = mapData.playerSpawnPosition
        worldNode.addChild(playerNode)

        // 4. Faceless NPCs (SPEC §8)
        let npcSpawns = [
            CGPoint(x: 38 * 32, y: 32 * 32),
            CGPoint(x: 44 * 32, y: 30 * 32),
            CGPoint(x: 24 * 32, y: 41 * 32),
            CGPoint(x: 54 * 32, y: 41 * 32),
            CGPoint(x: 24 * 32, y: 22 * 32),
            CGPoint(x: 50 * 32, y: 22 * 32)
        ]
        for (i, pos) in npcSpawns.enumerated() {
            let npc = NPCNode(id: "\(i)", position: pos, wanderRadius: 60.0)
            worldNode.addChild(npc)
            npcs.append(npc)
        }

        // 5. Camera Node
        sceneCamera = SKCameraNode()
        self.camera = sceneCamera
        addChild(sceneCamera)

        // 6. Atmospheric Dark Dusk Vignette & Radial Lantern Glow
        let vignetteTex = makeLanternVignetteTexture(size: CGSize(width: 512, height: 512))
        lightingOverlay = SKSpriteNode(texture: vignetteTex, size: CGSize(width: 900, height: 520))
        lightingOverlay.zPosition = 25
        lightingOverlay.blendMode = .alpha
        sceneCamera.addChild(lightingOverlay)

        // Initial Palette
        updateDusk(forMeanPosteriorSD: 0.30)
    }

    public override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        if let overlay = lightingOverlay {
            overlay.size = CGSize(width: max(850, size.width * 1.15), height: max(420, size.height * 1.15))
        }
    }

    private func makeLanternVignetteTexture(size: CGSize) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cgContext = ctx.cgContext
            let colorSpace = CGColorSpaceCreateDeviceRGB()

            let colors = [
                UIColor(red: 1.0, green: 0.88, blue: 0.60, alpha: 0.00).cgColor,
                UIColor(red: 0.95, green: 0.78, blue: 0.45, alpha: 0.10).cgColor,
                UIColor(red: 0.12, green: 0.15, blue: 0.28, alpha: 0.65).cgColor,
                UIColor(red: 0.04, green: 0.06, blue: 0.14, alpha: 0.88).cgColor,
                UIColor(red: 0.02, green: 0.03, blue: 0.08, alpha: 0.96).cgColor
            ] as CFArray

            let locations: [CGFloat] = [0.0, 0.22, 0.52, 0.80, 1.0]
            guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) else { return }

            let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
            let radius = max(size.width, size.height) * 0.50
            cgContext.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: radius,
                options: [.drawsAfterEndLocation]
            )
        }
        let tex = SKTexture(image: image)
        tex.filteringMode = .linear
        return tex
    }

    public func setInputVector(_ vector: CGVector) {
        self.inputVector = vector
    }

    /// SPEC §8.1 — palette and light decay on posterior confidence, not on time.
    ///
    /// The vignette used to run 0.70 → 0.95. That put a 70%-opacity darkness
    /// over the village on the very first frame, so a game SPEC §1 calls
    /// "cheerful" opened at night, and the whole five-step schedule then spanned
    /// 25% of alpha — a change small enough that the decay, which is the only
    /// signal the model is closing in, was invisible.
    ///
    /// It now opens nearly clear and ends genuinely dark, so the arc is the
    /// thing the player feels.
    public func updateDusk(forMeanPosteriorSD sd: Double) {
        guard let effectNode = worldEffectNode else { return }
        let step = paletteController.step(forMeanPosteriorSD: sd)
        paletteController.apply(to: effectNode, step: step)
        lightingOverlay?.alpha = Self.vignetteAlpha(forStep: step)
    }

    /// Exposed so the decay curve is pinned by a test rather than by eye.
    /// Monotonic, and never fully opaque — the player must still see the path.
    static func vignetteAlpha(forStep step: Double) -> CGFloat {
        let clamped = min(max(step, 0), 5)
        return CGFloat(0.06 + (clamped / 5.0) * 0.74)
    }

    public override func update(_ currentTime: TimeInterval) {
        guard let player = playerNode else { return }

        // Update player movement from input vector
        player.updateMovement(vector: inputVector)

        // 4 Hz Movement Sampling (SCHEMA §2)
        if currentTime - lastSampleTime >= 0.25 {
            lastSampleTime = currentTime
            if let sampler = movementSampler {
                sampler.updatePosition(
                    x: Double(player.position.x),
                    y: Double(player.position.y)
                )
            }
        }

        // Smooth Camera Follow with clamping
        updateCameraPosition()

        // Active Trigger Proximity & Metric Tracking
        updateTriggerProximity(currentTime: currentTime)

        // Eye Proximity Tracking
        updateEyeProximity(currentTime: currentTime)

        // The lantern task
        updateDeliveries()
    }

    /// Deliver on arrival, refill at the well. No prompt, no confirmation —
    /// walking up to a dark house with a lantern is the whole interaction.
    private func updateDeliveries() {
        guard let player = playerNode, let map = mapData else { return }

        if lanternsCarried > 0,
           let idx = undeliveredDoors.firstIndex(where: {
               hypot($0.x - player.position.x, $0.y - player.position.y) < Self.deliveryRadius
           }) {
            let door = undeliveredDoors.remove(at: idx)
            lanternsCarried -= 1
            lightWindow(at: door)
            onLanternDelivered?(lanternsCarried)
        }

        if lanternsCarried < Self.carryCapacity, !undeliveredDoors.isEmpty {
            let well = map.playerSpawnPosition
            if hypot(well.x - player.position.x, well.y - player.position.y) < Self.refillRadius {
                lanternsCarried = Self.carryCapacity
                onLanternsRefilled?(lanternsCarried)
            }
        }
    }

    /// A warm glow over the doorway. This is the only progress display the task
    /// gets, and it is diegetic — part of the village, not an overlay.
    private func lightWindow(at door: CGPoint) {
        guard litWindows[door] == nil else { return }
        let glow = SKSpriteNode(color: UIColor(red: 1.0, green: 0.83, blue: 0.45, alpha: 1.0),
                                size: CGSize(width: 26, height: 26))
        glow.position = CGPoint(x: door.x, y: door.y + 32)
        glow.zPosition = 7
        glow.blendMode = .add
        glow.alpha = 0
        addChild(glow)
        litWindows[door] = glow
        glow.run(.sequence([
            .fadeAlpha(to: 0.55, duration: 0.45),
            .repeatForever(.sequence([.fadeAlpha(to: 0.38, duration: 1.7),
                                      .fadeAlpha(to: 0.55, duration: 1.7)])),
        ]))
    }

    private func updateCameraPosition() {
        guard let player = playerNode, let cam = sceneCamera, let map = mapData else { return }

        let halfWidth = self.size.width / 2.0
        let halfHeight = self.size.height / 2.0

        let minX = halfWidth
        let maxX = map.worldSize.width - halfWidth
        let minY = halfHeight
        let maxY = map.worldSize.height - halfHeight

        let targetX = min(max(player.position.x, minX), maxX)
        let targetY = min(max(player.position.y, minY), maxY)

        // Smooth camera lerp
        let lerpFactor: CGFloat = 0.12
        cam.position.x += (targetX - cam.position.x) * lerpFactor
        cam.position.y += (targetY - cam.position.y) * lerpFactor
    }

    private func updateTriggerProximity(currentTime: TimeInterval) {
        guard let player = playerNode else { return }

        var nearestTrigger: ScenarioTriggerNode? = nil
        var nearestDistance: CGFloat = .infinity

        for trigger in triggers {
            let dist = hypot(player.position.x - trigger.position.x, player.position.y - trigger.position.y)
            if dist <= trigger.radius && dist < nearestDistance {
                nearestDistance = dist
                nearestTrigger = trigger
            }
        }

        if nearestTrigger !== activeTrigger {
            activeTrigger = nearestTrigger
            onActiveTriggerChanged?(activeTrigger)

            if activeTrigger != nil {
                // Entered new trigger zone
                zoneEntryTime = currentTime
                zoneLastMovementTime = currentTime
                zoneIdleDuration = 0.0
                zoneMinDistance = nearestDistance
                zoneBacktrackCount = 0
                zonePreviousDirection = player.currentDirection
            }
        } else if activeTrigger != nil {
            // Still in zone: track metrics
            if player.isMoving {
                zoneLastMovementTime = currentTime
                if let prevDir = zonePreviousDirection, prevDir != player.currentDirection {
                    // Reversal / backtrack
                    if (prevDir == .down && player.currentDirection == .up) ||
                       (prevDir == .up && player.currentDirection == .down) ||
                       (prevDir == .left && player.currentDirection == .right) ||
                       (prevDir == .right && player.currentDirection == .left) {
                        zoneBacktrackCount += 1
                    }
                }
                zonePreviousDirection = player.currentDirection
            } else {
                zoneIdleDuration += (currentTime - zoneLastMovementTime)
                zoneLastMovementTime = currentTime
            }
            zoneMinDistance = min(zoneMinDistance, nearestDistance)
        }
    }

    private func updateEyeProximity(currentTime: TimeInterval) {
        guard let player = playerNode, let eye = eyeNode else { return }
        let dist = hypot(player.position.x - eye.position.x, player.position.y - eye.position.y)
        let threeTilesDistance: CGFloat = 96.0

        if dist <= threeTilesDistance {
            if !isNearEye {
                isNearEye = true
                nearEyeEntryTime = currentTime
            } else {
                eyeApproachDurationMs += Int((currentTime - nearEyeEntryTime) * 1000)
                nearEyeEntryTime = currentTime
            }
        } else {
            isNearEye = false
        }
    }

    // MARK: - Scenario Metrics Extraction (SCHEMA §1, §7.1)

    public func currentScenarioMetrics() -> (approachFrac: Double, backtracks: Int, idleMs: Int) {
        guard let trigger = activeTrigger else {
            return (approachFrac: 0.5, backtracks: 0, idleMs: 0)
        }
        let approach = max(0.0, min(1.0, Double(1.0 - (zoneMinDistance / trigger.radius))))
        let idle = Int(zoneIdleDuration * 1000)
        return (approachFrac: approach, backtracks: zoneBacktrackCount, idleMs: idle)
    }

    // MARK: - In-Village Events (SPEC §6)

    /// §6.2 Predictive Shadow
    public func spawnShadow(predictedDestination: CGPoint, onComplete: @escaping () -> Void) {
        let shadow = ShadowNode()
        guard let cam = sceneCamera else { return }
        let angle = Double.random(in: 0...(2 * .pi))
        let spawnOffset = CGPoint(x: cos(angle) * (size.width / 2 + 30), y: sin(angle) * (size.height / 2 + 30))
        shadow.position = CGPoint(x: cam.position.x + spawnOffset.x, y: cam.position.y + spawnOffset.y)

        worldNode.addChild(shadow)
        shadow.walkToward(destination: predictedDestination, duration: 10.0, onComplete: onComplete)
    }

    /// §6.3 The Eye
    public func triggerEye(duration: TimeInterval = 3.0, onComplete: (() -> Void)? = nil) {
        eyeNode.flash(duration: duration, onComplete: onComplete)
    }
}
