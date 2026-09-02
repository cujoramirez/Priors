//
//  CharacterNode.swift
//  Priors
//
//  SpriteKit nodes for Player, Faceless NPC wanderers, and Predictive Shadow.
//

import SpriteKit

public enum PhysicsCategory {
    public static let none: UInt32 = 0
    public static let player: UInt32 = 0b1        // 1
    public static let boundary: UInt32 = 0b10     // 2 (walls, water, fences)
    public static let trigger: UInt32 = 0b100     // 4 (scenario trigger zones)
    public static let eye: UInt32 = 0b1000        // 8 (the eye location)
}

@MainActor
public class PlayerNode: SKSpriteNode {
    public private(set) var currentDirection: Direction = .down
    public private(set) var isMoving: Bool = false
    public let speedMultiplier: CGFloat = 110.0 // points per second

    private let walkActionKey = "player_walk_anim"

    /// The pool of light the Runner carries. SPEC §8 gives the lantern count
    /// the whole HUD and SPEC §4 makes lanterns the stake behind every price,
    /// so the light needs to exist in the world and not only as a number in a
    /// pill. It is also what separates the player from the villagers now that
    /// every figure is the same hooded silhouette.
    ///
    /// Purely decorative: it is drawn under the figure and reads by nothing.
    /// The dusk vignette darkens the village around it, so the pool is what
    /// the player actually navigates by as the palette decays.
    private let lanternGlow: SKSpriteNode = {
        let glow = SKSpriteNode(texture: PlayerNode.lanternGlowTexture(),
                                size: CGSize(width: 150, height: 150))
        glow.zPosition = -1
        glow.blendMode = .add
        glow.alpha = 0.55
        return glow
    }()

    public init() {
        let defaultTexture = VillageAssets.shared.playerIdleTexture(direction: .down)
        super.init(texture: defaultTexture, color: .clear, size: CGSize(width: 32, height: 32))
        self.name = "player"
        self.zPosition = 10
        addChild(lanternGlow)
        // A carried flame is never perfectly steady. Slow and shallow, so it
        // reads as flame rather than as a pulsing UI element.
        lanternGlow.run(.repeatForever(.sequence([
            .group([.fadeAlpha(to: 0.46, duration: 1.9), .scale(to: 0.94, duration: 1.9)]),
            .group([.fadeAlpha(to: 0.58, duration: 2.3), .scale(to: 1.04, duration: 2.3)]),
        ])))
        setupPhysics()
    }

    /// Soft warm radial falloff, built once and shared.
    private static var cachedGlow: SKTexture?
    private static func lanternGlowTexture() -> SKTexture {
        if let cached = cachedGlow { return cached }
        let side: CGFloat = 256
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let image = renderer.image { ctx in
            let colors = [
                UIColor(red: 1.00, green: 0.86, blue: 0.58, alpha: 0.85).cgColor,
                UIColor(red: 0.98, green: 0.70, blue: 0.34, alpha: 0.34).cgColor,
                UIColor(red: 0.85, green: 0.48, blue: 0.18, alpha: 0.00).cgColor,
            ] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: colors,
                                            locations: [0.0, 0.38, 1.0]) else { return }
            let centre = CGPoint(x: side / 2, y: side / 2)
            ctx.cgContext.drawRadialGradient(gradient,
                                             startCenter: centre, startRadius: 0,
                                             endCenter: centre, endRadius: side / 2,
                                             options: [])
        }
        let tex = SKTexture(image: image)
        cachedGlow = tex
        return tex
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupPhysics() {
        // Feet collider to allow top-down 2.5D overlap on buildings/trees
        let bodySize = CGSize(width: 16, height: 12)
        let bodyCenter = CGPoint(x: 0, y: -8)
        let body = SKPhysicsBody(rectangleOf: bodySize, center: bodyCenter)
        body.isDynamic = true
        body.allowsRotation = false
        body.affectedByGravity = false
        body.friction = 0.0
        body.restitution = 0.0
        body.linearDamping = 0.0
        body.categoryBitMask = PhysicsCategory.player
        body.collisionBitMask = PhysicsCategory.boundary
        body.contactTestBitMask = PhysicsCategory.trigger | PhysicsCategory.eye
        self.physicsBody = body
    }

    public func updateMovement(vector: CGVector) {
        let magnitude = hypot(vector.dx, vector.dy)
        let movingThreshold: CGFloat = 0.15

        if magnitude > movingThreshold {
            let targetDirection = Direction.from(vector: vector)
            if !isMoving || targetDirection != currentDirection {
                currentDirection = targetDirection
                startWalkAnimation()
            }
            isMoving = true

            // Set physics velocity
            let normalizedVector = CGVector(dx: vector.dx / magnitude, dy: vector.dy / magnitude)
            physicsBody?.velocity = CGVector(
                dx: normalizedVector.dx * speedMultiplier * magnitude,
                dy: normalizedVector.dy * speedMultiplier * magnitude
            )
        } else {
            if isMoving {
                stopWalkAnimation()
            }
            isMoving = false
            physicsBody?.velocity = .zero
        }
    }

    /// Tiny Town ships one character pose, so `left` is `right` mirrored. The
    /// flip lives here rather than in the atlas: duplicating a mirrored copy on
    /// the sheet would double the frames for no gain, and `xScale` is free.
    private func applyFacing() {
        xScale = currentDirection == .left ? -1 : 1
    }

    private func startWalkAnimation() {
        removeAction(forKey: walkActionKey)
        applyFacing()
        let frames = VillageAssets.shared.playerWalkCycle(direction: currentDirection)
        guard frames.count > 1 else {
            texture = frames.first
            return
        }
        let anim = SKAction.repeatForever(
            SKAction.animate(with: frames, timePerFrame: 0.16, resize: false, restore: false))
        run(anim, withKey: walkActionKey)
    }

    private func stopWalkAnimation() {
        removeAction(forKey: walkActionKey)
        applyFacing()
        texture = VillageAssets.shared.playerIdleTexture(direction: currentDirection)
    }
}

@MainActor
public class NPCNode: SKSpriteNode {
    public let villagerID: String
    private var currentDirection: Direction = .down
    private let walkActionKey = "npc_walk_anim"
    private var homePosition: CGPoint
    private var wanderRadius: CGFloat
    /// Which of the three faceless villager appearances this one uses. Derived
    /// from the id so a villager keeps the same look for the whole session.
    private let variant: Int

    public init(id: String, position: CGPoint, wanderRadius: CGFloat = 80.0) {
        self.villagerID = id
        self.homePosition = position
        self.wanderRadius = wanderRadius
        self.variant = abs(id.hashValue) % VillageAssets.shared.villagerVariantCount
        let defaultTexture = VillageAssets.shared.npcIdleTexture(variant: variant)
        super.init(texture: defaultTexture, color: .clear, size: CGSize(width: 32, height: 32))
        self.position = position
        self.name = "npc_\(id)"
        self.zPosition = 9

        // Setup feet collider
        let body = SKPhysicsBody(rectangleOf: CGSize(width: 14, height: 10), center: CGPoint(x: 0, y: -8))
        body.isDynamic = true
        body.allowsRotation = false
        body.affectedByGravity = false
        body.categoryBitMask = PhysicsCategory.boundary
        body.collisionBitMask = PhysicsCategory.player | PhysicsCategory.boundary
        self.physicsBody = body

        startWanderBehavior()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func startWanderBehavior() {
        let waitAction = SKAction.wait(forDuration: Double.random(in: 2.0...5.0))
        let wanderAction = SKAction.run { [weak self] in
            self?.wanderToRandomNearbyPoint()
        }
        run(SKAction.repeatForever(SKAction.sequence([waitAction, wanderAction])))
    }

    private func wanderToRandomNearbyPoint() {
        let angle = Double.random(in: 0...(2 * .pi))
        let distance = CGFloat.random(in: 20...wanderRadius)
        let targetPoint = CGPoint(
            x: homePosition.x + cos(angle) * distance,
            y: homePosition.y + sin(angle) * distance
        )

        let dx = targetPoint.x - position.x
        let dy = targetPoint.y - position.y
        let dir = Direction.from(vector: CGVector(dx: dx, dy: dy))
        currentDirection = dir
        // The pack has one facing; left is it mirrored, same as the player.
        xScale = dir == .left ? -1 : 1

        let walkFrames = VillageAssets.shared.npcWalkCycle(variant: variant)
        let animate = SKAction.repeatForever(SKAction.animate(with: walkFrames, timePerFrame: 0.15))
        let dist = hypot(dx, dy)
        let duration = TimeInterval(dist / 35.0)
        let move = SKAction.move(to: targetPoint, duration: duration)

        let endAction = SKAction.run { [weak self] in
            guard let self = self else { return }
            self.removeAction(forKey: self.walkActionKey)
            self.texture = VillageAssets.shared.npcIdleTexture(variant: self.variant)
        }

        run(animate, withKey: walkActionKey)
        run(SKAction.sequence([move, endAction]))
    }
}

@MainActor
public class ShadowNode: SKSpriteNode {
    public init() {
        let defaultTexture = VillageAssets.shared.playerIdleTexture(direction: .down)
        super.init(texture: defaultTexture, color: .clear, size: CGSize(width: 32, height: 32))
        self.alpha = 0.30 // SPEC §6.2: 30% alpha
        self.color = .gray
        self.colorBlendFactor = 0.7 // desaturated
        self.zPosition = 8
        self.name = "shadow"
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func walkToward(destination: CGPoint, duration: TimeInterval = 10.0, onComplete: @escaping () -> Void) {
        let dx = destination.x - position.x
        let dy = destination.y - position.y
        let dir = Direction.from(vector: CGVector(dx: dx, dy: dy))
        let frames = VillageAssets.shared.playerWalkCycle(direction: dir)
        let anim = SKAction.repeatForever(SKAction.animate(with: frames, timePerFrame: 0.15))
        let move = SKAction.move(to: destination, duration: duration)
        let fade = SKAction.fadeOut(withDuration: 1.5)

        run(anim)
        run(SKAction.sequence([
            move,
            fade,
            SKAction.run { onComplete() },
            SKAction.removeFromParent()
        ]))
    }
}
