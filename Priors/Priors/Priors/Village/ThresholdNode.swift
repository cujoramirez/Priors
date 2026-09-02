//
//  ThresholdNode.swift
//  Priors
//
//  SPEC §8.3 — a spatial decision (PATH/DETOUR/TRADE) is a threshold the
//  player walks across, not a modal. Crossing (getting within `commitRadius`
//  before leaving `radius`) is engaged: true; entering and leaving without
//  ever reaching `commitRadius` is engaged: false. VillageScene tracks the
//  actual crossing/leaving transition and owns the resolution; this node only
//  renders the band phrase and the band's visual intensity.
//
//  No physics body: resolution is purely distance-based in
//  `VillageScene.updateArmedDecision`. The node used to carry a sensor body
//  with `contactTestBitMask = .player`, which implied a contact-callback
//  mechanism that never existed — no `didBegin(_:)` was ever written.
//

import SpriteKit

@MainActor
public final class ThresholdNode: SKNode {
    /// The zone radius. Used before `super.init` (for the overlay) as well as
    /// after, which is why it is a static rather than a stored property.
    public static let zoneRadius: CGFloat = 36.0

    public let decision: LiveDecision
    public let radius: CGFloat = ThresholdNode.zoneRadius
    public let commitRadius: CGFloat = 14.0

    private let darknessOverlay: SKShapeNode
    private let phraseLabel: SKLabelNode

    public init(decision: LiveDecision) {
        self.decision = decision

        darknessOverlay = SKShapeNode(circleOfRadius: Self.zoneRadius)
        darknessOverlay.fillColor = .black
        darknessOverlay.strokeColor = .black
        darknessOverlay.isAntialiased = true
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
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 0.0 (barely dimmed, small) to 1.0 (near-black, filling the whole zone)
    /// — SPEC §8.2's "matching visual intensity" per band, generic across
    /// templates for this pass. Darkness, size and rim weight all move
    /// together (`DecisionIntensityStyle`) so adjacent bands separate on three
    /// channels at once rather than on ~0.09 of alpha. Bespoke per-template
    /// art (flame-gutter, wind-audible, etc.) is deferred to the art session
    /// (SPEC-GAME.md draft §6, not ratified into contract).
    public func setIntensity(_ intensity: Double) {
        let clamped = min(max(intensity, 0.0), 1.0)
        let r = Self.zoneRadius * DecisionIntensityStyle.poolRadiusFraction(clamped)
        darknessOverlay.path = CGPath(
            ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2),
            transform: nil
        )
        // Fill and rim carry their own alphas so the two channels stay
        // independent; the node's own `alpha` is left at 1 so it remains free
        // for the resolution fade-out.
        darknessOverlay.fillColor = SKColor(white: 0.0, alpha: DecisionIntensityStyle.poolAlpha(clamped))
        darknessOverlay.strokeColor = SKColor(white: 0.0, alpha: DecisionIntensityStyle.rimAlpha(clamped))
        darknessOverlay.lineWidth = DecisionIntensityStyle.rimWidth(clamped)
    }
}
