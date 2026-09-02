//
//  WaitingVillagerNode.swift
//  Priors
//
//  SPEC §8.3 — a social decision (ERROR/CREDIT/GIVE) is a villager who
//  approaches, stops, and waits with the band phrase above them, not a
//  modal. Holding Interact while facing them resolves engaged: true;
//  walking away resolves engaged: false (VillageScene tracks this, Task 9).
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

    private let sprite: SKSpriteNode
    private let phraseLabel: SKLabelNode
    private let variant: Int
    public private(set) var hasArrived: Bool = false

    public init(decision: LiveDecision, id: String) {
        self.decision = decision
        self.villagerID = id
        self.variant = abs(id.hashValue) % VillageAssets.shared.villagerVariantCount

        sprite = SKSpriteNode(texture: VillageAssets.shared.npcIdleTexture(variant: variant),
                               size: CGSize(width: 32, height: 32))
        sprite.zPosition = 9

        phraseLabel = SKLabelNode(fontNamed: "Menlo")
        phraseLabel.fontSize = 12
        phraseLabel.fontColor = SKColor(white: 0.9, alpha: 0.9)
        phraseLabel.position = CGPoint(x: 0, y: 30)
        phraseLabel.numberOfLines = 2
        phraseLabel.preferredMaxLayoutWidth = 160
        phraseLabel.horizontalAlignmentMode = .center
        phraseLabel.alpha = 0.0
        phraseLabel.text = decision.phrase
        phraseLabel.zPosition = 20

        super.init()
        self.name = "waiting_villager_\(id)"
        addChild(sprite)
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
                guard let self = self else { return }
                self.sprite.removeAction(forKey: "villager_walk")
                self.sprite.texture = VillageAssets.shared.npcIdleTexture(variant: self.variant)
                self.hasArrived = true
                self.phraseLabel.run(.fadeAlpha(to: 1.0, duration: 0.4))
            },
        ]))
    }

    /// SPEC §8.3's "holding Interact while facing them" — approximated as
    /// "close enough, and has finished arriving." Facing is not checked
    /// against the player's exact heading (the existing Direction enum is
    /// 4-way and would make this needlessly finicky); proximity while the
    /// interact button is enabled (VillageScene only enables it near a live
    /// decision, Task 9) is the actual gate.
    public func isPlayerClose(playerPosition: CGPoint) -> Bool {
        hasArrived && hypot(playerPosition.x - position.x, playerPosition.y - position.y) <= approachRadius
    }
}
