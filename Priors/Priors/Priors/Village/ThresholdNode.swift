//
//  ThresholdNode.swift
//  Priors
//
//  SPEC §8.3 — a spatial decision (PATH/DETOUR/TRADE) is a threshold the
//  player walks across, not a modal. Crossing (getting within `commitRadius`
//  before leaving `radius`) is engaged: true; entering and leaving without
//  ever reaching `commitRadius` is engaged: false. VillageScene tracks the
//  actual crossing/leaving transition (Task 9); this node only renders the
//  band phrase and the intensity, and carries the sensor physics body.
//

import SpriteKit

@MainActor
public final class ThresholdNode: SKNode {
    public let decision: LiveDecision
    public let radius: CGFloat = 36.0
    public let commitRadius: CGFloat = 14.0

    private let darknessOverlay: SKShapeNode
    private let phraseLabel: SKLabelNode

    public init(decision: LiveDecision) {
        self.decision = decision

        darknessOverlay = SKShapeNode(circleOfRadius: 36.0)
        darknessOverlay.fillColor = .black
        darknessOverlay.strokeColor = .clear
        darknessOverlay.zPosition = 4
        darknessOverlay.blendMode = .alpha

        phraseLabel = SKLabelNode(fontNamed: "Menlo")
        phraseLabel.fontSize = 12
        phraseLabel.fontColor = SKColor(white: 0.9, alpha: 0.9)
        phraseLabel.position = CGPoint(x: 0, y: 44)
        phraseLabel.numberOfLines = 2
        phraseLabel.preferredMaxLayoutWidth = 160
        phraseLabel.horizontalAlignmentMode = .center
        phraseLabel.text = decision.phrase
        phraseLabel.zPosition = 20

        super.init()
        self.name = "threshold_live"
        self.zPosition = 3

        addChild(darknessOverlay)
        addChild(phraseLabel)
        setIntensity(decision.visualIntensity)

        let body = SKPhysicsBody(circleOfRadius: radius)
        body.isDynamic = false
        body.categoryBitMask = PhysicsCategory.trigger
        body.contactTestBitMask = PhysicsCategory.player
        body.collisionBitMask = PhysicsCategory.none
        self.physicsBody = body
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 0.0 (barely dimmed) to 1.0 (near-black) — SPEC §8.2's "matching visual
    /// intensity" per band, generic across templates for this pass. Bespoke
    /// per-template art (flame-gutter, wind-audible, etc.) is deferred to the
    /// art session (SPEC-GAME.md draft §6, not ratified into contract).
    public func setIntensity(_ intensity: Double) {
        let clamped = min(max(intensity, 0.0), 1.0)
        darknessOverlay.alpha = CGFloat(0.08 + clamped * 0.55)
    }
}
