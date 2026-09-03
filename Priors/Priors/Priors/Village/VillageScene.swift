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
public class VillageScene: SKScene {
    // Root Effect Node for continuous palette decay (SPEC §8.1)
    public private(set) var worldEffectNode: SKEffectNode!
    public private(set) var worldNode: SKNode!

    // Entities
    public private(set) var playerNode: PlayerNode!
    public private(set) var npcs: [NPCNode] = []
    public private(set) var eyeNode: EyeNode!
    public private(set) var mapData: VillageMapData!
    public private(set) var decisionLocations: [DecisionLocation] = []

    // Camera & Lighting
    public private(set) var sceneCamera: SKCameraNode!
    public private(set) var lightingOverlay: SKSpriteNode!

    // Controls and Movement
    private var inputVector: CGVector = .zero
    public var movementSampler: MovementSampler?
    private var lastSampleTime: TimeInterval = 0.0

    // MARK: - Live decision (SPEC §8.3)
    //
    // Exactly one decision is ever live at a time. `armDecision` places
    // either a ThresholdNode (spatial) or a WaitingVillagerNode (social);
    // resolution is detected here, in `update(_:)`, and reported through
    // `onLiveDecisionResolved` rather than any button callback for spatial
    // decisions — the world resolves itself.
    private var armedThreshold: ThresholdNode?
    private var armedVillager: WaitingVillagerNode?
    private var retiredDecisionLayer: SKNode!
    // One tuple parameter, not two arguments: the resolution travels as a
    // single named tuple, so the extra parens around it are load-bearing.
    //
    // `zoneDwellSeconds` is SPEC §8.3's hesitation: "time between entering a
    // threshold's zone and resolving it." Only the scene knows that instant —
    // the coordinator's arm time is the moment the *previous* decision
    // resolved, half a village away — so it is measured here and travels with
    // the resolution. It is what `rt_ms` is made of (SCHEMA §1).
    public var onLiveDecisionResolved: (((engaged: Bool, zoneDwellSeconds: TimeInterval, metrics: (approachFrac: Double, backtracks: Int, idleMs: Int))) -> Void)?

    private var isInsideArmedZone: Bool = false
    private var isInteractHeld: Bool = false
    private var interactHoldStartTime: TimeInterval?
    private static let socialHoldDuration: TimeInterval = 0.6

    // MARK: - The task (SPEC §8)
    //
    // "Task: deliver lanterns to houses before dark." It is the cover story for
    // the 30 decisions, not a game to win: SPEC §2.4 forbids a score and a fail
    // state, so nothing is counted, nothing is timed and nothing is lost by
    // ignoring it. Delivery happens on proximity rather than on the interact
    // button, which stays reserved for scenarios.
    //
    // Progress is shown by the windows themselves: a dark house asks, a lit
    // one has been answered. SPEC §8.4 permits a HUD marker now, and exactly
    // one is used — the well indicator, and only when the player's hands are
    // empty. Nothing marks, counts or routes toward a *decision* (§2.9).
    public private(set) var undeliveredDoors: [CGPoint] = []
    private var litWindows: [CGPoint: SKNode] = [:]
    /// A cold pool over every door that still has no light in it. SPEC §8.4:
    /// "an unlit window that reads as asking". Driven per frame rather than by
    /// an `SKAction`, because the approach warmth (`doorWarmth`) writes the
    /// same alpha and scale and two writers would fight.
    private var askingWindows: [CGPoint: SKSpriteNode] = [:]
    /// The carried lantern's light reaching a dark doorway as the player
    /// closes on it. A separate warm sprite rather than a tint on the cold
    /// one, because brightening a blue pool only makes it bluer — what the
    /// approach has to read as is *warmth arriving*.
    private var approachGlows: [CGPoint: SKSpriteNode] = [:]
    private var wellPool: SKSpriteNode?
    private var wellIndicator: SKNode?

    /// Exposed for tests: the chevron cannot be verified by rendering it,
    /// because a camera's children do not come back through
    /// `SKView.texture(from:)`. Its placement is asserted instead.
    var wellIndicatorNode: SKNode? { wellIndicator }

    public var askingWindowCount: Int { askingWindows.count }
    public var litWindowCount: Int { litWindows.count }

    /// True when the player is carrying nothing and houses are still dark —
    /// the one genuine dead end in the game. SPEC §8.4 permits the marker;
    /// carrying a lantern is its own instruction, so it goes away again.
    public private(set) var wellIndicatorActive: Bool = false
    public var onLanternDelivered: ((Int) -> Void)?
    public var onLanternsRefilled: ((Int) -> Void)?
    public private(set) var lanternsCarried: Int = 3
    /// SPEC §4 — how many lanterns the well is willing to hand back. Starts at
    /// capacity and is lowered permanently by decision-driven losses, so a
    /// lantern gambled away on a PATH or given away on a GIVE stays gone for
    /// the run. Refilling to a flat `carryCapacity` refunded every loss at the
    /// next well visit, which left the template prices with no textural stake
    /// behind them at all.
    public private(set) var carryAllowance: Int = 3
    public static let carryCapacity = 3
    static let deliveryRadius: CGFloat = 40
    private static let refillRadius: CGFloat = 56
    /// How far out a dark house starts responding to being approached.
    static let doorWarmthRadius: CGFloat = 120

    /// 1 at the doorstep, 0 at `doorWarmthRadius`, smooth all the way between.
    ///
    /// Continuity is the whole point: a step change at `deliveryRadius` would
    /// make delivery read as a trigger the player crossed. A house that warms
    /// as you close on it makes it somewhere you arrived.
    static func doorWarmth(distance: CGFloat) -> CGFloat {
        guard distance < doorWarmthRadius else { return 0 }
        let t = 1.0 - max(distance, 0) / doorWarmthRadius
        // Was `t * t`, which left the first two thirds of the approach with
        // almost no warmth in it — the house only responded once the player
        // was practically on the doorstep, which is where they no longer need
        // telling. Eases in earlier while staying strictly monotonic.
        return t * (0.4 + 0.6 * t)
    }

    public func setLanternsCarried(_ count: Int) {
        self.lanternsCarried = max(0, count)
    }

    /// The ceiling the well refills to. Clamped to `carryCapacity` so a TRADE
    /// win cannot raise the run's standing allowance above what the Runner can
    /// physically carry.
    public func setCarryAllowance(_ allowance: Int) {
        self.carryAllowance = min(Self.carryCapacity, max(0, allowance))
    }

    // Zone Exploration Metrics (SCHEMA §1, §7.1)
    /// nil until the player is inside the armed zone. Was a `0.0` sentinel,
    /// which is a value `currentTime` genuinely takes in tests.
    private var zoneEntryTime: TimeInterval?
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

        // No `contactDelegate`: nothing in this scene resolves on contact.
        // Decision zones are distance-based (`updateArmedDecision`), and the
        // delegate that used to be installed here had no `didBegin(_:)`
        // behind it — every contact was computed and discarded.
        physicsWorld.gravity = .zero

        // 1. World Effect Node (Dusk shift)
        worldEffectNode = SKEffectNode()
        worldEffectNode.shouldRasterize = false
        addChild(worldEffectNode)

        worldNode = SKNode()
        worldEffectNode.addChild(worldNode)

        // Resolved decision nodes are moved here to fade out. They leave
        // `worldNode.children` on the resolving frame, so "exactly one
        // decision is live" stays literally true, but they are still on
        // screen for the length of the fade — a villager that vanished the
        // instant the player walked past was hard to tell apart from SPEC
        // §8.3's forbidden "reacts to being declined."
        retiredDecisionLayer = SKNode()
        retiredDecisionLayer.name = "retired_decisions"
        worldNode.addChild(retiredDecisionLayer)

        // 2. Build 80x60 Village Tilemap
        let buildResult = VillageMapBuilder.shared.buildVillage(in: worldNode)
        self.mapData = buildResult.mapData
        self.undeliveredDoors = buildResult.mapData.doorPositions
        self.decisionLocations = buildResult.decisionLocations
        self.eyeNode = buildResult.eyeNode

        // Every dark house asks (SPEC §8.4).
        for door in undeliveredDoors {
            let lightPoint = Self.windowPosition(forDoor: door)

            let ask = SKSpriteNode(texture: Self.coldPoolTexture(),
                                   size: CGSize(width: 76, height: 76))
            ask.position = lightPoint
            ask.zPosition = 6.5
            ask.blendMode = .alpha
            ask.alpha = Self.askingBaseAlpha
            worldNode.addChild(ask)
            askingWindows[door] = ask

            let reach = SKSpriteNode(texture: Self.warmPoolTexture(),
                                     size: CGSize(width: 96, height: 96))
            reach.position = lightPoint
            reach.zPosition = 6.6
            reach.blendMode = .add
            reach.alpha = 0
            worldNode.addChild(reach)
            approachGlows[door] = reach
        }

        // The well already has a sprite; this is the light on it, so that
        // "where does light come from" is answerable from across a field.
        let pool = SKSpriteNode(texture: Self.warmPoolTexture(),
                                size: CGSize(width: 150, height: 150))
        pool.position = mapData.playerSpawnPosition
        pool.zPosition = 5.5
        pool.blendMode = .add
        pool.alpha = 0.30
        worldNode.addChild(pool)
        wellPool = pool

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

        // 5b. The well indicator — a chevron on the camera, so it is screen
        // furniture rather than something standing in the village. Hidden
        // until the player is empty-handed with houses still dark.
        let chevron = SKShapeNode(path: Self.chevronPath())
        chevron.fillColor = UIColor(red: 1.0, green: 0.86, blue: 0.58, alpha: 0.85)
        chevron.strokeColor = .clear
        chevron.zPosition = 30
        chevron.alpha = 0
        chevron.isHidden = true
        sceneCamera.addChild(chevron)
        wellIndicator = chevron

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
    /// The vignette first ran 0.70 → 0.95 (opened at night, and the whole
    /// five-step schedule spanned 25% of alpha — a change too small to feel).
    /// It was then flattened to 0.06 → 0.80, which overcorrected: at 6% there
    /// is no lantern pool and no framing at all, so the village read as a
    /// brightly-lit map in full daylight and SPEC §8.1's "warm amber" never
    /// appeared on screen.
    ///
    /// It now opens at a golden-hour 0.42 — enough that the lantern carves a
    /// visible pool out of the light — and ends at 0.86. It stops short of
    /// 0.95 because the palette anchors darken too, and the two together were
    /// leaving the back half of a session unreadable.
    /// Still monotonic, still never fully opaque: the player must always be
    /// able to see the path.
    public func updateDusk(forMeanPosteriorSD sd: Double) {
        guard let effectNode = worldEffectNode else { return }
        let step = paletteController.step(forMeanPosteriorSD: sd)
        paletteController.apply(to: effectNode, step: step)
        lightingOverlay?.alpha = Self.vignetteAlpha(forStep: step)
        // SPEC §4 and the prologue both make the point that the valley lives
        // on carried fire. As the palette decays the lantern is increasingly
        // the only thing the player can navigate by, so its reach grows to
        // meet the dark rather than being swallowed with everything else.
        playerNode?.setLanternReach(Self.lanternReach(forStep: step))
    }

    /// The carried light grows as the world darkens: 1.0 at golden hour,
    /// 1.6 at full night. Presentation only — it reaches nothing the model
    /// reads, and it is what keeps the path legible once the vignette and
    /// the palette anchors have both bottomed out.
    static func lanternReach(forStep step: Double) -> CGFloat {
        let clamped = min(max(step, 0), 5)
        return CGFloat(1.0 + (clamped / 5.0) * 0.6)
    }

    /// Exposed so the decay curve is pinned by a test rather than by eye.
    /// Monotonic, and never fully opaque — the player must still see the path.
    static func vignetteAlpha(forStep step: Double) -> CGFloat {
        let clamped = min(max(step, 0), 5)
        return CGFloat(0.42 + (clamped / 5.0) * 0.44)
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
        updateCameraPosition(currentTime: currentTime)

        // Armed live decision: zone dwell, crossing / hold resolution
        updateArmedDecision(currentTime: currentTime)

        // Eye Proximity Tracking
        updateEyeProximity(currentTime: currentTime)

        // The lantern task
        updateDeliveries()

        // And what the village says about it (SPEC §8.4)
        updateTaskLegibility(currentTime: currentTime)
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
            // Removed outright rather than faded out. A fade is an SKAction,
            // and an SKAction is a dependency on the scene actually running —
            // the light coming on covers the cut, and the swap is then true
            // the frame it happens rather than 0.35s later.
            askingWindows.removeValue(forKey: door)?.removeFromParent()
            approachGlows.removeValue(forKey: door)?.removeFromParent()
            lightWindow(at: door)
            onLanternDelivered?(lanternsCarried)
        }

        // Top up to the standing allowance, not to capacity — see
        // `carryAllowance`. When losses have driven the allowance to zero the
        // well has nothing to give, and the run ends the way it earned.
        if lanternsCarried < carryAllowance, !undeliveredDoors.isEmpty {
            let well = map.playerSpawnPosition
            if hypot(well.x - player.position.x, well.y - player.position.y) < Self.refillRadius {
                lanternsCarried = carryAllowance
                onLanternsRefilled?(lanternsCarried)
            }
        }
    }

    /// A warm glow over the doorway: the house has been answered.
    ///
    /// This used to be a 26x26 solid tan square with additive blending, which
    /// against a dark village read as a missing texture rather than as light —
    /// the owner identified these squares as a rendering fault. It is a soft
    /// radial falloff now, the same technique as the carried lantern's pool,
    /// and it lives in `worldNode` so it decays with the palette like every
    /// other thing in the village. It was parented to the scene before, which
    /// put the one warm point in the frame outside the dusk filter.
    private func lightWindow(at door: CGPoint) {
        guard litWindows[door] == nil else { return }
        let glow = SKSpriteNode(texture: Self.warmPoolTexture(),
                                size: CGSize(width: 108, height: 108))
        glow.position = Self.windowPosition(forDoor: door)
        glow.zPosition = 7
        glow.blendMode = .add
        // Lit outright, not faded up. A lamp coming on is instant, and more
        // to the point the alpha must not depend on an SKAction having run:
        // the breath below is decoration, and if it never runs the window is
        // still correctly lit.
        glow.alpha = 0.55
        worldNode.addChild(glow)
        litWindows[door] = glow
        glow.run(.repeatForever(.sequence([.fadeAlpha(to: 0.38, duration: 1.7),
                                           .fadeAlpha(to: 0.55, duration: 1.7)])))
    }

    // MARK: - Task legibility (SPEC §8.4)

    /// Where a door's light sits: on the doorstep, spilling onto the ground
    /// in front of the door.
    ///
    /// It was briefly lifted onto the doorway itself, which made it invisible
    /// — the cottages' door row is grey-blue stone, and a cold pool on
    /// grey-blue stone is nothing at all. On the ground it reads against both
    /// grass and path, and light falling out of a doorway is what a top-down
    /// view can actually show.
    static func windowPosition(forDoor door: CGPoint) -> CGPoint {
        CGPoint(x: door.x, y: door.y + 26)
    }

    private static let askingBaseAlpha: CGFloat = 0.62

    /// Dark houses breathe, brighten as they are approached, and the well
    /// gets pointed at when the player has nothing left to give.
    ///
    /// Presentation only. Nothing here is read by the model, and nothing here
    /// touches a decision location — SPEC §2.9 forbids marking one.
    private func updateTaskLegibility(currentTime: TimeInterval) {
        guard let player = playerNode else { return }

        let carrying = lanternsCarried > 0
        // A slow, shallow breath so the pools read as light rather than as a
        // pulsing UI element. Same intent as the carried lantern's flicker.
        let breath = 0.88 + 0.12 * CGFloat(sin(currentTime * 0.9))

        for (door, ask) in askingWindows {
            let d = hypot(door.x - player.position.x, door.y - player.position.y)
            // A house only answers an approach that could actually light it.
            let warmth = carrying ? Self.doorWarmth(distance: d) : 0
            // The cold recedes as the warmth arrives, rather than the two
            // simply summing into a brighter blue.
            ask.alpha = Self.askingBaseAlpha * breath * (1.0 - 0.55 * warmth)
            approachGlows[door]?.alpha = warmth * 0.85
            approachGlows[door]?.setScale(0.75 + warmth * 0.45)
        }

        wellPool?.alpha = 0.30 * breath

        updateWellIndicator(playerPosition: player.position)
    }

    /// SPEC §8.4's one permitted marker. It points at the well, never at a
    /// decision, and only while the player is stranded: no light in hand and
    /// houses still dark.
    private func updateWellIndicator(playerPosition: CGPoint) {
        guard let indicator = wellIndicator, let map = mapData else { return }

        let stranded = lanternsCarried == 0 && !undeliveredDoors.isEmpty
        wellIndicatorActive = stranded

        // Shown and hidden directly rather than faded. Everything about this
        // marker's state is a function of the current frame, and an SKAction
        // would make its alpha depend on the scene having run — the same trap
        // the asking pools and the lit windows were in.
        guard stranded else {
            indicator.isHidden = true
            indicator.alpha = 0
            return
        }

        let well = map.playerSpawnPosition
        let dx = well.x - playerPosition.x
        let dy = well.y - playerPosition.y
        let angle = atan2(dy, dx)

        // Ride an inset ellipse at the screen edge, pointing the way the well
        // lies. The camera is the frame, so this is in camera-local points.
        let rx = max(size.width / 2 - 56, 40)
        let ry = max(size.height / 2 - 56, 40)
        indicator.position = CGPoint(x: cos(angle) * rx, y: sin(angle) * ry)
        indicator.zRotation = angle

        indicator.isHidden = false
        indicator.alpha = 0.8
    }

    /// A stubby triangle pointing along +x, so `zRotation` alone aims it.
    private static func chevronPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 13, y: 0))
        path.addLine(to: CGPoint(x: -8, y: 9))
        path.addLine(to: CGPoint(x: -4, y: 0))
        path.addLine(to: CGPoint(x: -8, y: -9))
        path.closeSubpath()
        return path
    }

    private static var cachedWarmPool: SKTexture?
    private static var cachedColdPool: SKTexture?

    /// The light of an answered house, and of the well.
    static func warmPoolTexture() -> SKTexture {
        if let cached = cachedWarmPool { return cached }
        let tex = radialPool(colors: [
            UIColor(red: 1.00, green: 0.88, blue: 0.62, alpha: 0.92),
            UIColor(red: 0.99, green: 0.72, blue: 0.36, alpha: 0.38),
            UIColor(red: 0.86, green: 0.48, blue: 0.18, alpha: 0.00),
        ])
        cachedWarmPool = tex
        return tex
    }

    /// The absence of it. Cold and dim, so a dark house reads as asking
    /// without ever reading as a marker someone placed there.
    static func coldPoolTexture() -> SKTexture {
        if let cached = cachedColdPool { return cached }
        let tex = radialPool(colors: [
            UIColor(red: 0.44, green: 0.56, blue: 0.86, alpha: 0.95),
            UIColor(red: 0.26, green: 0.34, blue: 0.62, alpha: 0.55),
            UIColor(red: 0.10, green: 0.14, blue: 0.30, alpha: 0.00),
        ])
        cachedColdPool = tex
        return tex
    }

    private static func radialPool(colors: [UIColor]) -> SKTexture {
        let side: CGFloat = 256
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let image = renderer.image { ctx in
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: colors.map { $0.cgColor } as CFArray,
                                            locations: [0.0, 0.40, 1.0]) else { return }
            let centre = CGPoint(x: side / 2, y: side / 2)
            ctx.cgContext.drawRadialGradient(gradient,
                                             startCenter: centre, startRadius: 0,
                                             endCenter: centre, endRadius: side / 2,
                                             options: [])
        }
        let tex = SKTexture(image: image)
        tex.filteringMode = .linear
        return tex
    }

    /// Seconds since the previous frame, clamped. Used only for presentation
    /// smoothing — never for anything SCHEMA §1 records, which all read
    /// `currentTime` directly.
    private var lastFrameTime: TimeInterval?
    /// Camera smoothing rate, per second. Chosen so that at 60fps a frame
    /// moves the camera the same 12% it did when this was a flat per-frame
    /// lerp: 1 - exp(-7.67/60) = 0.12.
    private static let cameraFollowRate: Double = 7.67

    private func updateCameraPosition(currentTime: TimeInterval) {
        guard let player = playerNode, let cam = sceneCamera, let map = mapData else { return }

        let halfWidth = self.size.width / 2.0
        let halfHeight = self.size.height / 2.0

        let minX = halfWidth
        let maxX = map.worldSize.width - halfWidth
        let minY = halfHeight
        let maxY = map.worldSize.height - halfHeight

        let targetX = min(max(player.position.x, minX), maxX)
        let targetY = min(max(player.position.y, minY), maxY)

        // Smooth camera lerp, frame-rate independent. A flat per-frame factor
        // made the camera converge twice as fast on a 120Hz ProMotion device
        // as on a 60Hz one — the same walk framed differently depending on the
        // hardware. Exponential smoothing against real elapsed time instead.
        // dt is clamped so a stalled frame (a breakpoint, a backgrounded app,
        // a test stepping `update` by whole seconds) cannot snap the camera.
        guard let previous = lastFrameTime else {
            // First frame. An SKCameraNode starts at the world origin — the
            // bottom-left corner of the map — so easing from there meant the
            // village opened on an unrequested swoop across the rooftops
            // before settling on the player. Start framed correctly instead.
            lastFrameTime = currentTime
            cam.position = CGPoint(x: targetX, y: targetY)
            return
        }
        let dt = min(max(currentTime - previous, 0), 0.05)
        lastFrameTime = currentTime
        let lerpFactor = CGFloat(1.0 - exp(-Self.cameraFollowRate * dt))
        cam.position.x += (targetX - cam.position.x) * lerpFactor
        cam.position.y += (targetY - cam.position.y) * lerpFactor
    }

    /// True only when a social decision is armed and the player is close
    /// enough to start holding Interact — drives VirtualControlsView's
    /// `canInteract`.
    public var canInteractNow: Bool {
        guard let villager = armedVillager, let player = playerNode else { return false }
        return villager.isPlayerClose(playerPosition: player.position)
    }

    /// Idempotent by contract: only a genuine false->true / true->false
    /// transition does anything. A repeated `true` (a per-frame poll, a
    /// re-fired SwiftUI onChange) must not restart the hold timer, or every
    /// social decision would resolve as a decline. Task 8's VirtualControls
    /// happens to de-duplicate today; this does not rely on that.
    public func setInteractPressed(_ pressed: Bool) {
        guard pressed != isInteractHeld else { return }
        isInteractHeld = pressed
        interactHoldStartTime = pressed ? nil : interactHoldStartTime
    }

    private func updateArmedDecision(currentTime: TimeInterval) {
        guard let player = playerNode else { return }

        if let threshold = armedThreshold {
            let dist = hypot(player.position.x - threshold.position.x,
                             player.position.y - threshold.position.y)
            let inZone = dist <= threshold.radius

            if inZone, !isInsideArmedZone {
                isInsideArmedZone = true
                // SPEC §8.3 — this instant, not the arm instant, is where
                // `rt_ms` starts.
                zoneEntryTime = currentTime
                zoneLastMovementTime = currentTime
                zoneIdleDuration = 0.0
                zoneMinDistance = dist
                zoneBacktrackCount = 0
                zonePreviousDirection = player.currentDirection
            } else if inZone {
                if player.isMoving {
                    zoneLastMovementTime = currentTime
                    if let prevDir = zonePreviousDirection, prevDir != player.currentDirection,
                       isOpposite(prevDir, player.currentDirection) {
                        zoneBacktrackCount += 1
                    }
                    zonePreviousDirection = player.currentDirection
                } else {
                    zoneIdleDuration += (currentTime - zoneLastMovementTime)
                    zoneLastMovementTime = currentTime
                }
                zoneMinDistance = min(zoneMinDistance, dist)
            } else if isInsideArmedZone {
                // Left the zone: resolve now. Crossing = got within
                // commitRadius before leaving; otherwise a decline.
                isInsideArmedZone = false
                let engaged = zoneMinDistance <= threshold.commitRadius
                let metrics = currentZoneMetrics(zoneRadius: threshold.radius)
                let dwell = zoneDwellSeconds(at: currentTime)
                retire(threshold)
                armedThreshold = nil
                zoneEntryTime = nil
                // Everything above is reset first: the callback re-enters
                // `armDecision` synchronously.
                onLiveDecisionResolved?((engaged: engaged, zoneDwellSeconds: dwell, metrics: metrics))
            }
            return
        }

        if let villager = armedVillager {
            let close = villager.isPlayerClose(playerPosition: player.position)
            let declineDistance = villager.approachRadius * 2.0
            let dist = hypot(player.position.x - villager.position.x,
                             player.position.y - villager.position.y)

            // Approach-phase zone dwell, tracked before the hold branch so it
            // runs on every frame the player is in the zone — including the
            // frames they spend holding Interact. Same instrumentation the
            // spatial branch uses, so a social decision's approachFrac and
            // backtracks are observed quantities rather than constants. The
            // zone here is the decline radius, which opens once the villager
            // has stopped and the player has come inside it.
            if villager.hasArrived, dist <= declineDistance {
                if zoneEntryTime == nil {
                    // Same as the spatial case: `rt_ms` starts here, on first
                    // approach, not when the decision was armed (SPEC §8.3).
                    zoneEntryTime = currentTime
                    zoneLastMovementTime = currentTime
                    zoneIdleDuration = 0.0
                    zoneMinDistance = dist
                    zoneBacktrackCount = 0
                    zonePreviousDirection = player.currentDirection
                } else {
                    if player.isMoving {
                        zoneLastMovementTime = currentTime
                        if let prevDir = zonePreviousDirection, prevDir != player.currentDirection,
                           isOpposite(prevDir, player.currentDirection) {
                            zoneBacktrackCount += 1
                        }
                        zonePreviousDirection = player.currentDirection
                    } else {
                        zoneIdleDuration += (currentTime - zoneLastMovementTime)
                        zoneLastMovementTime = currentTime
                    }
                    zoneMinDistance = min(zoneMinDistance, dist)
                }
            }

            if close, isInteractHeld {
                if interactHoldStartTime == nil { interactHoldStartTime = currentTime }
                if currentTime - (interactHoldStartTime ?? currentTime) >= Self.socialHoldDuration {
                    let metrics = currentZoneMetrics(zoneRadius: declineDistance)
                    let dwell = zoneDwellSeconds(at: currentTime)
                    retire(villager)
                    armedVillager = nil
                    interactHoldStartTime = nil
                    zoneEntryTime = nil
                    onLiveDecisionResolved?((engaged: true, zoneDwellSeconds: dwell, metrics: metrics))
                }
                return
            }
            interactHoldStartTime = nil

            if villager.hasArrived, dist > declineDistance, zoneEntryTime != nil {
                let metrics = currentZoneMetrics(zoneRadius: declineDistance)
                let dwell = zoneDwellSeconds(at: currentTime)
                retire(villager)
                armedVillager = nil
                zoneEntryTime = nil
                onLiveDecisionResolved?((engaged: false, zoneDwellSeconds: dwell, metrics: metrics))
            }
        }
    }

    private func isOpposite(_ a: Direction, _ b: Direction) -> Bool {
        (a == .down && b == .up) || (a == .up && b == .down)
            || (a == .left && b == .right) || (a == .right && b == .left)
    }

    /// SCHEMA §1's three observed zone quantities, for both halves of §8.3 —
    /// the social branch measures them against the decline radius, and is
    /// otherwise identical.
    ///
    /// `idleMs` is "ms **stationary** inside the scenario zone". The social
    /// branch used to compute its own, from total elapsed time in the zone,
    /// which is a different quantity: a player who paced around the villager
    /// for four seconds without ever standing still was logged as four
    /// seconds idle.
    private func currentZoneMetrics(zoneRadius: CGFloat) -> (approachFrac: Double, backtracks: Int, idleMs: Int) {
        let approach = max(0.0, min(1.0, Double(1.0 - (zoneMinDistance / zoneRadius))))
        return (approachFrac: approach, backtracks: zoneBacktrackCount, idleMs: Int(zoneIdleDuration * 1000))
    }

    /// SPEC §8.3's hesitation — how long the player has been inside the armed
    /// zone. 0 if they somehow resolved without entering it.
    private func zoneDwellSeconds(at currentTime: TimeInterval) -> TimeInterval {
        guard let entry = zoneEntryTime else { return 0.0 }
        return max(0.0, currentTime - entry)
    }

    /// Moves a resolved decision node out of the live world and fades it,
    /// rather than deleting it under the player's eyes (SPEC §8.3).
    private func retire(_ node: SKNode) {
        guard let layer = retiredDecisionLayer else {
            node.removeFromParent()
            return
        }
        node.removeFromParent()
        layer.addChild(node)
        node.run(.sequence([.fadeOut(withDuration: 0.6), .removeFromParent()]))
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

    /// SPEC §8.3 — arms exactly one decision at a time. Removes whatever was
    /// previously armed first (should never happen in practice, since
    /// VillageCoordinator only arms the next slot after the current one
    /// resolves, but this keeps the invariant true even under a
    /// double-call).
    public func armDecision(_ decision: LiveDecision, at location: DecisionLocation) {
        if let previous = armedThreshold { retire(previous) }
        armedThreshold = nil
        if let previous = armedVillager { retire(previous) }
        armedVillager = nil
        isInsideArmedZone = false
        isInteractHeld = false
        interactHoldStartTime = nil
        zoneEntryTime = nil

        if decision.isSpatial {
            let node = ThresholdNode(decision: decision)
            node.position = location.position
            worldNode.addChild(node)
            armedThreshold = node
        } else {
            let node = WaitingVillagerNode(decision: decision, id: "social_\(location.id)")
            let placement = villagerPlacement(for: location.position)
            worldNode.addChild(node)
            node.walkIn(to: placement.stand, from: placement.origin)
            armedVillager = node
        }
    }

    /// Where a waiting villager stands, and where it walks in from.
    ///
    /// Both used to be unchecked: the villager was placed on the decision
    /// anchor and walked in from a random point up to ~85pt away, so it could
    /// materialise inside a cottage or on the pond and walk out through the
    /// geometry. Six of the thirty authored anchors are features rather than
    /// floor — a door, a pier, a cellar lip. A threshold does not care (it is
    /// a zone drawn on the ground, and the player crosses near it) but a
    /// villager is a body, so it stands on the nearest walkable ground to the
    /// anchor and approaches along a line that is walkable end to end.
    ///
    /// The approach ring is sampled from a random start angle, so the
    /// direction the villager comes from stays unpredictable, and shrinks if
    /// the spot is hemmed in.
    func villagerPlacement(for anchor: CGPoint) -> (origin: CGPoint, stand: CGPoint) {
        guard let map = mapData else { return (anchor, anchor) }
        let stand = nearestWalkablePoint(to: anchor, in: map)
        let startAngle = CGFloat.random(in: 0..<(2 * .pi))
        for distance in [CGFloat(80), 56, 34] {
            for i in 0..<12 {
                let angle = startAngle + CGFloat(i) * (.pi / 6.0)
                let candidate = CGPoint(x: stand.x + cos(angle) * distance,
                                        y: stand.y + sin(angle) * distance)
                if map.isWalkable(worldPoint: candidate),
                   map.isWalkablePath(from: candidate, to: stand) {
                    return (candidate, stand)
                }
            }
        }
        // Hemmed in on every side: stand there without a walk-in rather than
        // walking through a wall to arrive.
        return (stand, stand)
    }

    private func nearestWalkablePoint(to anchor: CGPoint, in map: VillageMapData) -> CGPoint {
        if map.isWalkable(worldPoint: anchor) { return anchor }
        let tile = VillageMapBuilder.tileSize
        var best: (point: CGPoint, distance: CGFloat)?
        for step in 1...3 {
            let radius = tile * CGFloat(step)
            for i in 0..<16 {
                let angle = CGFloat(i) * (.pi / 8.0)
                let candidate = CGPoint(x: anchor.x + cos(angle) * radius,
                                        y: anchor.y + sin(angle) * radius)
                guard map.isWalkable(worldPoint: candidate) else { continue }
                let d = hypot(candidate.x - anchor.x, candidate.y - anchor.y)
                if best == nil || d < best!.distance { best = (candidate, d) }
            }
            if let found = best { return found.point }
        }
        return anchor
    }
}
