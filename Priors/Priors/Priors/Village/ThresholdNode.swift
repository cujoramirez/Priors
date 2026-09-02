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
    /// Same reason as `zoneRadius`: the commit sill is built before
    /// `super.init`, so the radius cannot come from the instance property.
    /// Both now read this, rather than the sill hardcoding a second 14.0 that
    /// could silently drift from `commitRadius`.
    public static let commitZoneRadius: CGFloat = 14.0

    public let decision: LiveDecision
    public let radius: CGFloat = ThresholdNode.zoneRadius
    public let commitRadius: CGFloat = ThresholdNode.commitZoneRadius

    private let darknessOverlay: SKShapeNode
    private let phraseLabel: SKLabelNode
    private let textPill: SKShapeNode
    /// The crossing itself: a ring of set paving stones at the zone edge and a
    /// worn stone lip at the commit radius.
    ///
    /// Without these the node was a dark circle on the ground, which at low
    /// intensity read as a patch of mud and at high intensity as a hole — and
    /// SPEC §8.2 makes band DISTINCTNESS the load-bearing variable, so a
    /// threshold that does not read as a threshold is a measurement problem
    /// and not only an ugly one. SPEC §8.3 calls a spatial decision "a marked
    /// crossing approachable from any angle (a cellar lip, a hedge gap, a
    /// gate)", so the marking is in contract, and a radially symmetric ring
    /// keeps every approach angle equivalent.
    private let markerRing: SKNode
    private let commitSill: SKShapeNode

    public init(decision: LiveDecision) {
        self.decision = decision

        darknessOverlay = SKShapeNode(circleOfRadius: Self.zoneRadius)
        darknessOverlay.fillColor = .black
        darknessOverlay.strokeColor = .black
        darknessOverlay.isAntialiased = true
        darknessOverlay.zPosition = 4
        darknessOverlay.blendMode = .alpha

        // Menlo at 12pt over a textured tilemap read as debug output and
        // was marginal to read at arm's length. The phrase is one half of
        // SPEC §8.2's price channel, so its legibility is part of the
        // instrument, not decoration.
        phraseLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        phraseLabel.fontSize = 14
        phraseLabel.fontColor = SKColor(white: 0.95, alpha: 0.95)
        phraseLabel.position = CGPoint(x: 0, y: 44)
        phraseLabel.numberOfLines = 2
        phraseLabel.preferredMaxLayoutWidth = 160
        phraseLabel.horizontalAlignmentMode = .center
        phraseLabel.text = decision.phrase
        phraseLabel.zPosition = 20

        // Backing pill for readability over the tilemap. Sized from the
        // label's own laid-out frame rather than a fixed rect: the rect was
        // measured for Menlo 12 and the second line of a two-line phrase
        // spilled straight out of it the moment the type changed.
        textPill = SKShapeNode()
        textPill.fillColor = SKColor(white: 0.05, alpha: 0.75)
        textPill.strokeColor = SKColor(white: 1.0, alpha: 0.15)
        textPill.lineWidth = 1.0
        textPill.isAntialiased = true
        textPill.zPosition = 19

        // A ring of set stones at the zone edge. Twelve is enough to read as
        // deliberate placement rather than scatter, at any approach angle.
        markerRing = SKNode()
        markerRing.zPosition = 5
        let stoneCount = 12
        for i in 0..<stoneCount {
            let angle = (CGFloat(i) / CGFloat(stoneCount)) * 2 * .pi
            let stone = SKShapeNode(rectOf: CGSize(width: 7, height: 5), cornerRadius: 1.5)
            stone.position = CGPoint(x: cos(angle) * Self.zoneRadius,
                                     y: sin(angle) * Self.zoneRadius)
            stone.zRotation = angle
            // Set stone catching the last of the light, with a dark seated
            // edge. Deliberately near-white at source: the dusk filter scales
            // green by 0.70 and blue by 0.52 at step 0 and harder later, so a
            // mid-grey stone lands as dark brown and stops reading as stone.
            stone.fillColor = SKColor(red: 0.94, green: 0.92, blue: 0.88, alpha: 0.95)
            stone.strokeColor = SKColor(red: 0.18, green: 0.15, blue: 0.14, alpha: 0.85)
            stone.lineWidth = 1.0
            stone.isAntialiased = true
            markerRing.addChild(stone)
        }

        // The lip you step over. SPEC §8.3 resolves a crossing on reaching
        // `commitRadius`, so the player is entitled to see where that is —
        // a threshold whose edge is invisible is not a threshold.
        commitSill = SKShapeNode(circleOfRadius: Self.commitZoneRadius)
        commitSill.fillColor = .clear
        commitSill.strokeColor = SKColor(red: 0.96, green: 0.92, blue: 0.84, alpha: 0.50)
        commitSill.lineWidth = 1.5
        commitSill.isAntialiased = true
        commitSill.zPosition = 5

        super.init()
        self.name = "threshold_live"
        self.zPosition = 3

        addChild(markerRing)
        addChild(commitSill)
        addChild(darknessOverlay)
        addChild(textPill)
        addChild(phraseLabel)
        Self.fitPill(textPill, to: phraseLabel)
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
        // Soft fill, crisp rim — see `DecisionIntensityStyle.poolFillTexture`.
        darknessOverlay.fillTexture = DecisionIntensityStyle.poolFillTexture()
        darknessOverlay.fillColor = SKColor(white: 0.0, alpha: DecisionIntensityStyle.poolAlpha(clamped))
        darknessOverlay.strokeColor = SKColor(white: 0.0, alpha: DecisionIntensityStyle.rimAlpha(clamped))
        darknessOverlay.lineWidth = DecisionIntensityStyle.rimWidth(clamped)
    }

    /// Fits the backing pill to the phrase after SpriteKit has laid the label
    /// out. `calculateAccumulatedFrame()` is only meaningful once the label is
    /// in the tree with its text set, so this runs after `addChild`.
    private static func fitPill(_ pill: SKShapeNode, to label: SKLabelNode) {
        let bounds = label.calculateAccumulatedFrame()
        guard bounds.width > 0, bounds.height > 0 else { return }
        let padded = bounds.insetBy(dx: -10, dy: -7)
        pill.path = CGPath(roundedRect: padded, cornerWidth: 7, cornerHeight: 7, transform: nil)
    }

}
