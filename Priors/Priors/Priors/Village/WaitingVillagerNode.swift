//
//  WaitingVillagerNode.swift
//  Priors
//
//  SPEC §8.3 — a social decision (ERROR/CREDIT/GIVE) is a villager who
//  approaches, stops, and waits with the band phrase above them, not a
//  modal. Holding Interact while facing them resolves engaged: true;
//  walking away resolves engaged: false (VillageScene tracks this).
//
//  Never turns to track the player — SPEC §8.3 forbids villager attention
//  that resembles watching, since it would confound the eye manipulation
//  (SPEC §6.3). This node picks its facing once, when it stops, and holds it.
//
//  Uses a straight-line SKAction.move for the walk-in, matching the existing
//  NPCNode/ShadowNode pattern. GameplayKit pathfinding is out of scope for
//  this plan (SPEC-GAME.md draft §5, not ratified into contract this pass).
//

import SpriteKit

@MainActor
public final class WaitingVillagerNode: SKNode {
    public let decision: LiveDecision
    public let villagerID: String
    public let approachRadius: CGFloat = 40.0
    /// The pool of darkness the villager stands in, sized to read at the same
    /// scale as a threshold's zone.
    public static let poolRadius: CGFloat = 30.0

    private let sprite: SKSpriteNode
    private let phraseLabel: SKLabelNode
    private let textPill: SKShapeNode
    /// SPEC §8.2's "one matching visual intensity per band" — the social half
    /// of it. The band was reaching the player through the phrase alone here,
    /// while the spatial half had both channels. Same mapping as
    /// `ThresholdNode` (`DecisionIntensityStyle`), so a band reads the same
    /// however it arrives. It is a property of the price, not of the player:
    /// it is set once on arrival and never changes, so the villager still
    /// never reacts to being approached or declined (SPEC §8.3 / §6.3).
    private let darknessPool: SKShapeNode
    private let variant: Int
    private var walkDestination: CGPoint?
    public private(set) var hasArrived: Bool = false

    public init(decision: LiveDecision, id: String) {
        self.decision = decision
        self.villagerID = id
        self.variant = abs(id.hashValue) % VillageAssets.shared.villagerVariantCount

        let intensity = decision.visualIntensity
        let r = Self.poolRadius * DecisionIntensityStyle.poolRadiusFraction(intensity)
        darknessPool = SKShapeNode(ellipseIn: CGRect(x: -r, y: -r - 12, width: r * 2, height: r * 1.3))
        darknessPool.fillColor = SKColor(white: 0.0, alpha: DecisionIntensityStyle.poolAlpha(intensity))
        darknessPool.strokeColor = SKColor(white: 0.0, alpha: DecisionIntensityStyle.rimAlpha(intensity))
        darknessPool.lineWidth = DecisionIntensityStyle.rimWidth(intensity)
        darknessPool.isAntialiased = true
        darknessPool.blendMode = .alpha
        darknessPool.zPosition = 4
        // Hidden during the walk-in: until the villager stops, they are just
        // a villager. The price appears with the phrase, both at once.
        darknessPool.alpha = 0.0

        sprite = SKSpriteNode(texture: VillageAssets.shared.npcIdleTexture(variant: variant),
                               size: CGSize(width: 32, height: 32))
        sprite.zPosition = 9
        sprite.color = .black
        sprite.colorBlendFactor = 0.0

        phraseLabel = SKLabelNode(fontNamed: "Menlo")
        phraseLabel.fontSize = 12
        phraseLabel.fontColor = SKColor(white: 0.95, alpha: 0.95)
        phraseLabel.position = CGPoint(x: 0, y: 30)
        phraseLabel.numberOfLines = 2
        phraseLabel.preferredMaxLayoutWidth = 160
        phraseLabel.horizontalAlignmentMode = .center
        phraseLabel.alpha = 0.0
        phraseLabel.text = decision.phrase
        phraseLabel.zPosition = 20

        // Translucent dark backing pill for high-contrast readability over tilemaps
        let pillRect = CGRect(x: -90, y: 20, width: 180, height: 38)
        textPill = SKShapeNode(rect: pillRect, cornerRadius: 6)
        textPill.fillColor = SKColor(white: 0.05, alpha: 0.75)
        textPill.strokeColor = SKColor(white: 1.0, alpha: 0.15)
        textPill.lineWidth = 1.0
        textPill.isAntialiased = true
        textPill.zPosition = 19
        textPill.alpha = 0.0

        super.init()
        self.name = "waiting_villager_\(id)"
        addChild(darknessPool)
        addChild(sprite)
        addChild(textPill)
        addChild(phraseLabel)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Walks in a straight line from `from` to `to`, then shows the phrase
    /// and holds position. Speed matches NPCNode's wander speed (35pt/s) so
    /// arrival doesn't read as urgent or alarming.
    public func walkIn(to destination: CGPoint, from origin: CGPoint) {
        position = origin
        walkDestination = destination
        let dx = destination.x - origin.x, dy = destination.y - origin.y
        let dir = Direction.from(vector: CGVector(dx: dx, dy: dy))
        sprite.xScale = dir == .left ? -1 : 1
        let walkFrames = VillageAssets.shared.npcWalkCycle(variant: variant)
        let animate = SKAction.repeatForever(SKAction.animate(with: walkFrames, timePerFrame: 0.15))
        let distance = hypot(dx, dy)
        let move = SKAction.move(to: destination, duration: TimeInterval(distance / 35.0))
        sprite.run(animate, withKey: "villager_walk")

        run(SKAction.sequence([
            move,
            SKAction.run { [weak self] in
                self?.completeArrival()
            },
        ]))
    }

    /// Everything that happens the moment the villager stops: the walk cycle
    /// ends, the phrase fades in, and the band's visual intensity appears
    /// with it. Called from `walkIn`'s SKAction completion in production.
    private func completeArrival() {
        guard !hasArrived else { return }
        sprite.removeAction(forKey: "villager_walk")
        sprite.texture = VillageAssets.shared.npcIdleTexture(variant: variant)
        hasArrived = true
        phraseLabel.run(.fadeAlpha(to: 1.0, duration: 0.4))
        textPill.run(.fadeAlpha(to: 1.0, duration: 0.4))
        darknessPool.run(.fadeAlpha(to: 1.0, duration: 0.4))
        sprite.run(.colorize(withColorBlendFactor: DecisionIntensityStyle.figureShading(decision.visualIntensity),
                             duration: 0.4))
    }

    #if DEBUG
    /// TEST SUPPORT ONLY — not called from production code.
    ///
    /// Arrival is driven by an `SKAction` completion, which needs a render
    /// loop no unit test has, so the entire hold-to-engage and walk-away-to-
    /// decline path (11 of every 30 decisions) was unreachable from tests.
    /// This runs the exact same completion body `walkIn` runs, and snaps the
    /// node to the destination the walk was heading for, so a test sees the
    /// state a device sees a few seconds after arming. Production behaviour
    /// is untouched.
    func simulateArrivalForTesting() {
        removeAllActions()
        if let destination = walkDestination { position = destination }
        completeArrival()
    }
    #endif

    /// SPEC §8.3's "holding Interact while facing them" — approximated as
    /// "close enough, and has finished arriving." Facing is not checked
    /// against the player's exact heading (the existing Direction enum is
    /// 4-way and would make this needlessly finicky); proximity while the
    /// interact button is enabled (VillageScene only enables it near a live
    /// decision) is the actual gate.
    public func isPlayerClose(playerPosition: CGPoint) -> Bool {
        hasArrived && hypot(playerPosition.x - position.x, playerPosition.y - position.y) <= approachRadius
    }
}
