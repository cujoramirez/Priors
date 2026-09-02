//
//  VillageMapBuilder.swift
//  Priors
//
//  Constructs the 80x60 village tilemap with >=30% dead space, physics boundaries,
//  trigger zones, and in-village event anchors per SPEC §8.
//

import SpriteKit
import PriorsEngine

/// One of the 30 pre-built spots a decision can be armed at. Ordinary
/// scenery until VillageCoordinator arms it (SPEC §8.3) — no physics body,
/// no visual, until then.
public struct DecisionLocation: Sendable {
    public let id: Int
    public let position: CGPoint
    public let regionName: String
    /// theta_e -> a spatial threshold (PATH/DETOUR/TRADE); theta_i -> a
    /// waiting villager (ERROR/CREDIT/GIVE). SPEC §3.1/§3.2's split is
    /// exactly the trait split, so this one field is enough to route arming.
    public let trait: Trait
}

@MainActor
public class EyeNode: SKNode {
    private let dot1: SKShapeNode
    private let dot2: SKShapeNode

    public override init() {
        // SPEC §6.3: Two white 2x2 pixel dots
        dot1 = SKShapeNode(rectOf: CGSize(width: 2, height: 2))
        dot1.fillColor = .white
        dot1.strokeColor = .clear
        dot1.position = CGPoint(x: -2, y: 0)

        dot2 = SKShapeNode(rectOf: CGSize(width: 2, height: 2))
        dot2.fillColor = .white
        dot2.strokeColor = .clear
        dot2.position = CGPoint(x: 2, y: 0)

        super.init()
        self.name = "the_eye"
        self.zPosition = 15
        self.alpha = 0.0

        addChild(dot1)
        addChild(dot2)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func flash(duration: TimeInterval = 3.0, onComplete: (() -> Void)? = nil) {
        self.alpha = 1.0
        let wait = SKAction.wait(forDuration: duration)
        let fadeOut = SKAction.fadeOut(withDuration: 0.1)
        let finish = SKAction.run { onComplete?() }
        run(SKAction.sequence([wait, fadeOut, finish]))
    }
}

public struct VillageMapData {
    public let width: Int = 80
    public let height: Int = 60
    public let tileSize: CGFloat = 32.0

    public var worldSize: CGSize {
        CGSize(width: CGFloat(width) * tileSize, height: CGFloat(height) * tileSize)
    }

    public let playerSpawnPosition: CGPoint = CGPoint(x: 40 * 32, y: 30 * 32)
    public let eyePosition: CGPoint = CGPoint(x: 42 * 32, y: 38 * 32)

    /// Front doors, in world coordinates. SPEC §8's task is to deliver lanterns
    /// to the houses before dark, so these are the only objective the village
    /// has — and there is no marker pointing at them, per the HUD rule.
    public var doorPositions: [CGPoint] = []

    public var walkableTileCount: Int = 0
    public var deadSpaceTileCount: Int = 0
    public var deadSpaceFraction: Double {
        walkableTileCount > 0 ? Double(deadSpaceTileCount) / Double(walkableTileCount) : 0.0
    }

    /// `[row][col]`, true where the tile is floor rather than wall, water,
    /// cottage or canopy — i.e. the builder's grid codes 0 and 1.
    ///
    /// Published so the scene can check a spot before putting something in
    /// the world at it. A waiting villager (SPEC §8.3) used to spawn at an
    /// unchecked random offset, which could drop it inside a cottage or on
    /// the pond and walk it through geometry.
    public var walkableTiles: [[Bool]] = []

    public func isWalkable(worldPoint point: CGPoint) -> Bool {
        guard !walkableTiles.isEmpty else { return true }
        let col = Int((point.x / tileSize).rounded(.down))
        let row = Int((point.y / tileSize).rounded(.down))
        guard row >= 0, row < walkableTiles.count,
              col >= 0, col < walkableTiles[row].count else { return false }
        return walkableTiles[row][col]
    }

    /// True when every point along the straight segment is walkable, sampled
    /// at half-tile steps. A villager walks in a straight line, so a walkable
    /// start and end is not enough on its own.
    public func isWalkablePath(from start: CGPoint, to end: CGPoint) -> Bool {
        let distance = hypot(end.x - start.x, end.y - start.y)
        let steps = max(1, Int((distance / (tileSize / 2)).rounded(.up)))
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let p = CGPoint(x: start.x + (end.x - start.x) * t,
                            y: start.y + (end.y - start.y) * t)
            if !isWalkable(worldPoint: p) { return false }
        }
        return true
    }
}

@MainActor
public final class VillageMapBuilder {
    public static let shared = VillageMapBuilder()

    public static let mapCols = 80
    public static let mapRows = 60
    public static let tileSize: CGFloat = 32.0

    // Grid tracking (0 = empty/walkable deadspace, 1 = path/objective, 2 = solid wall/water)
    private var grid: [[Int]] = Array(repeating: Array(repeating: 0, count: 80), count: 60)

    /// Ground is one `SKTileMapNode`, not 4,800 sprites.
    ///
    /// The village is 80x60. Building it as individual `SKSpriteNode`s meant
    /// ~4,800 nodes for grass alone, plus ~560 perimeter physics bodies and ~60
    /// for the pond — all constructed synchronously while the player waited on
    /// the temperament tap. `SKTileMapNode` draws a whole layer in one batch,
    /// and the boundaries are now a handful of rectangles instead of one body
    /// per tile.
    private var doorPositions: [CGPoint] = []
    private var groundMap: SKTileMapNode?
    private var canopyMap: SKTileMapNode?
    private var tileGroups: [TileType: SKTileGroup] = [:]

    public init() {}

    private func makeTileMap() -> (SKTileMapNode, SKTileMapNode) {
        if tileGroups.isEmpty {
            var all: [SKTileGroup] = []
            for type in TileType.allCases {
                let def = SKTileDefinition(
                    texture: VillageAssets.shared.texture(for: type),
                    size: CGSize(width: Self.tileSize, height: Self.tileSize))
                let group = SKTileGroup(tileDefinition: def)
                group.name = "tile_\(type.rawValue)"
                tileGroups[type] = group
                all.append(group)
            }
            cachedTileSet = SKTileSet(tileGroups: all, tileSetType: .grid)
        }
        let size = CGSize(width: Self.tileSize, height: Self.tileSize)
        func map(_ z: CGFloat, _ name: String) -> SKTileMapNode {
            let m = SKTileMapNode(tileSet: cachedTileSet!, columns: Self.mapCols,
                                  rows: Self.mapRows, tileSize: size)
            m.anchorPoint = .zero      // tile (0,0) centred at (16,16), matching the old sprites
            m.position = .zero
            m.zPosition = z
            m.name = name
            return m
        }
        return (map(0, "ground_layer"), map(6, "canopy_layer"))
    }

    private var cachedTileSet: SKTileSet?

    private func setGround(_ col: Int, _ row: Int, _ tile: TileType, code: Int) {
        guard let g = tileGroups[tile] else { return }
        groundMap?.setTileGroup(g, forColumn: col, row: row)
        grid[row][col] = code
    }

    private func setCanopy(_ col: Int, _ row: Int, _ tile: TileType) {
        guard let g = tileGroups[tile] else { return }
        canopyMap?.setTileGroup(g, forColumn: col, row: row)
        grid[row][col] = 2
    }

    /// One static body over a tile-aligned rectangle, replacing per-tile bodies.
    private func addAreaCollider(colRange: ClosedRange<Int>, rowRange: ClosedRange<Int>,
                                 to node: SKNode) {
        let w = CGFloat(colRange.count) * Self.tileSize
        let h = CGFloat(rowRange.count) * Self.tileSize
        let collider = SKNode()
        collider.position = CGPoint(
            x: CGFloat(colRange.lowerBound) * Self.tileSize + w / 2,
            y: CGFloat(rowRange.lowerBound) * Self.tileSize + h / 2)
        let body = SKPhysicsBody(rectangleOf: CGSize(width: w, height: h))
        body.isDynamic = false
        body.categoryBitMask = PhysicsCategory.boundary
        body.collisionBitMask = PhysicsCategory.player
        collider.physicsBody = body
        node.addChild(collider)
    }

    public func buildVillage(in rootNode: SKNode) -> (mapData: VillageMapData, decisionLocations: [DecisionLocation], eyeNode: EyeNode) {
        let assets = VillageAssets.shared
        grid = Array(repeating: Array(repeating: 0, count: Self.mapCols), count: Self.mapRows)
        doorPositions = []

        let (ground, canopy) = makeTileMap()
        groundMap = ground
        canopyMap = canopy
        rootNode.addChild(ground)
        rootNode.addChild(canopy)
        let groundNode = ground

        let structuresNode = SKNode()
        structuresNode.name = "structures_layer"
        structuresNode.zPosition = 5
        rootNode.addChild(structuresNode)

        // 1. Fill ground with grass (90% lush grass, 10% natural scattered wildflowers)
        for r in 0..<Self.mapRows {
            for c in 0..<Self.mapCols {
                let hashVal = (c * 73 + r * 151) & 0x7FFFFFFF
                let grassTile: TileType
                if hashVal % 19 == 0 {
                    grassTile = .grassVar1
                } else if hashVal % 23 == 0 {
                    grassTile = .grassVar2
                } else {
                    grassTile = .grass
                }
                setGround(c, r, grassTile, code: 0)
            }
        }
        _ = assets

        // 2. Build Perimeter Boundaries (Dense woods / hedges)
        buildPerimeterBoundaries(in: structuresNode)

        // 3. Build Paths Connecting Village Center
        buildPathNetwork(in: groundNode)

        // 4. Build Water Pond & Stream
        buildPondAndStream(in: groundNode, structures: structuresNode)

        // 5. Build Cottages & Buildings
        buildCottages(in: structuresNode)

        // 6. Decision locations (no physics/visuals until armed — SPEC §8.3)
        let decisionLocations = buildDecisionLocations()

        // 7. Build Eye Node
        let eyeNode = EyeNode()
        eyeNode.position = CGPoint(x: 42 * Self.tileSize, y: 38 * Self.tileSize)
        rootNode.addChild(eyeNode)

        // 8. Calculate Dead Space Ratio
        var walkable = 0
        var deadSpace = 0
        var walkableTiles = Array(repeating: Array(repeating: false, count: Self.mapCols),
                                  count: Self.mapRows)
        for r in 0..<Self.mapRows {
            for c in 0..<Self.mapCols {
                walkableTiles[r][c] = grid[r][c] != 2
            }
        }
        for r in 2..<(Self.mapRows - 2) {
            for c in 2..<(Self.mapCols - 2) {
                if grid[r][c] == 0 {
                    walkable += 1
                    deadSpace += 1
                } else if grid[r][c] == 1 {
                    walkable += 1
                }
            }
        }

        var mapData = VillageMapData()
        mapData.doorPositions = doorPositions
        mapData.walkableTileCount = walkable
        mapData.deadSpaceTileCount = deadSpace
        mapData.walkableTiles = walkableTiles

        return (mapData, decisionLocations, eyeNode)
    }

    /// A two-tile band of woods around the map, drawn into the canopy layer and
    /// blocked by four rectangles rather than ~560 individual physics bodies.
    private func buildPerimeterBoundaries(in node: SKNode) {
        for c in 0..<Self.mapCols {
            setCanopy(c, 0, .tree)
            setCanopy(c, 1, .tree)
            setCanopy(c, Self.mapRows - 1, .tree)
            setCanopy(c, Self.mapRows - 2, .tree)
        }
        for r in 2..<(Self.mapRows - 2) {
            setCanopy(0, r, .tree)
            setCanopy(1, r, .tree)
            setCanopy(Self.mapCols - 1, r, .tree)
            setCanopy(Self.mapCols - 2, r, .tree)
        }
        addAreaCollider(colRange: 0...(Self.mapCols - 1), rowRange: 0...1, to: node)
        addAreaCollider(colRange: 0...(Self.mapCols - 1),
                        rowRange: (Self.mapRows - 2)...(Self.mapRows - 1), to: node)
        addAreaCollider(colRange: 0...1, rowRange: 2...(Self.mapRows - 3), to: node)
        addAreaCollider(colRange: (Self.mapCols - 2)...(Self.mapCols - 1),
                        rowRange: 2...(Self.mapRows - 3), to: node)
    }

    private func buildPathNetwork(in node: SKNode) {
        let assets = VillageAssets.shared

        // Main East-West Highway (y: 28..30, x: 15..65)
        for c in 15...65 {
            placeGroundTile(col: c, row: 29, tile: .pathHorizontal, in: node, code: 1)
            placeGroundTile(col: c, row: 30, tile: .pathHorizontal, in: node, code: 1)
        }

        // North-South Avenue (x: 39..41, y: 12..48)
        for r in 12...48 {
            placeGroundTile(col: 39, row: r, tile: .pathVertical, in: node, code: 1)
            placeGroundTile(col: 40, row: r, tile: .pathVertical, in: node, code: 1)
            placeGroundTile(col: 41, row: r, tile: .pathVertical, in: node, code: 1)
        }

        // Branch Paths to Cottages
        for c in 20...38 { placeGroundTile(col: c, row: 42, tile: .pathHorizontal, in: node, code: 1) }
        for c in 42...60 { placeGroundTile(col: c, row: 42, tile: .pathHorizontal, in: node, code: 1) }
        for c in 20...38 { placeGroundTile(col: c, row: 18, tile: .pathHorizontal, in: node, code: 1) }
        for c in 42...60 { placeGroundTile(col: c, row: 18, tile: .pathHorizontal, in: node, code: 1) }

        // Village Center Plaza (x: 37..43, y: 27..33)
        for r in 27...33 {
            for c in 37...43 {
                placeGroundTile(col: c, row: r, tile: .pathCenter, in: node, code: 1)
            }
        }

        // Village Well
        let wellSprite = SKSpriteNode(texture: assets.texture(for: .well), size: CGSize(width: Self.tileSize, height: Self.tileSize))
        wellSprite.position = CGPoint(x: 40 * Self.tileSize + Self.tileSize / 2, y: 30 * Self.tileSize + Self.tileSize / 2)
        wellSprite.zPosition = 6
        node.addChild(wellSprite)
        grid[30][40] = 2
    }

    private func buildPondAndStream(in ground: SKNode, structures: SKNode) {
        let assets = VillageAssets.shared
        // Pond in South-East quadrant (x: 52..62, y: 10..18)
        for r in 10...18 {
            for c in 52...62 {
                let isEdge = (r == 10 || r == 18 || c == 52 || c == 62)
                setGround(c, r, isEdge ? .waterEdge : .water, code: 2)
            }
        }
        // Deep water: one body for the interior, not one per tile.
        addAreaCollider(colRange: 53...61, rowRange: 11...17, to: structures)
        _ = ground
        _ = assets
    }

    private func buildCottages(in node: SKNode) {
        // 7 distinct cottages
        buildCottage(originCol: 22, originRow: 44, widthCols: 6, heightRows: 4, name: "Cottage_NorthWest", in: node)
        buildCottage(originCol: 52, originRow: 44, widthCols: 6, heightRows: 4, name: "Cottage_NorthEast", in: node)
        buildCottage(originCol: 18, originRow: 32, widthCols: 5, heightRows: 4, name: "Cottage_West", in: node)
        buildCottage(originCol: 56, originRow: 32, widthCols: 5, heightRows: 4, name: "Cottage_East", in: node)
        buildCottage(originCol: 22, originRow: 20, widthCols: 6, heightRows: 4, name: "Cottage_SouthWest", in: node)
        buildCottage(originCol: 48, originRow: 20, widthCols: 6, heightRows: 4, name: "Cottage_SouthEast", in: node)
        buildCottage(originCol: 37, originRow: 36, widthCols: 7, heightRows: 5, name: "TownHall_Center", in: node)
    }

    private func buildCottage(originCol: Int, originRow: Int, widthCols: Int, heightRows: Int, name: String, in node: SKNode) {
        let assets = VillageAssets.shared

        for r in 0..<heightRows {
            for c in 0..<widthCols {
                let col = originCol + c
                let row = originRow + r
                let pos = CGPoint(x: CGFloat(col) * Self.tileSize + Self.tileSize / 2, y: CGFloat(row) * Self.tileSize + Self.tileSize / 2)

                let tile: TileType
                if r >= heightRows - 2 {
                    // Roof
                    tile = (c == 1 && r == heightRows - 1) ? .chimney : .roofRed
                } else if r == 0 && c == widthCols / 2 {
                    // Door
                    doorPositions.append(CGPoint(x: pos.x, y: pos.y - Self.tileSize))
                    tile = .doorClosed
                } else if r == 1 && (c == 1 || c == widthCols - 2) {
                    // Window
                    tile = .window
                } else {
                    // Wall
                    tile = (r == 0) ? .wallStone : .wallWood
                }

                let sprite = SKSpriteNode(texture: assets.texture(for: tile), size: CGSize(width: Self.tileSize, height: Self.tileSize))
                sprite.position = pos
                sprite.zPosition = 6
                node.addChild(sprite)
                grid[row][col] = 2
            }
        }

        // Solid collider over the whole building footprint.
        //
        // This used to span `heightRows - 1` starting one row up, which left the
        // entire bottom row — the wall row carrying the door — with no collider,
        // so the player walked straight through the front of every cottage. The
        // footprint now matches the tiles that were actually drawn.
        let footprintWidth = CGFloat(widthCols) * Self.tileSize
        let footprintHeight = CGFloat(heightRows) * Self.tileSize
        let center = CGPoint(
            x: CGFloat(originCol) * Self.tileSize + footprintWidth / 2,
            y: CGFloat(originRow) * Self.tileSize + footprintHeight / 2
        )
        let houseCollider = SKNode()
        houseCollider.position = center
        let body = SKPhysicsBody(rectangleOf: CGSize(width: footprintWidth, height: footprintHeight))
        body.isDynamic = false
        body.categoryBitMask = PhysicsCategory.boundary
        body.collisionBitMask = PhysicsCategory.player
        houseCollider.physicsBody = body
        node.addChild(houseCollider)
    }

    /// 30 pre-built spots, unchanged in position/name from the original
    /// layout — only the label narrows from a specific template hint to the
    /// trait the spot's flavour fits (SPEC §5.1 reserves template choice for
    /// ADO, never a location).
    private func buildDecisionLocations() -> [DecisionLocation] {
        let configs: [(x: Int, y: Int, name: String, trait: Trait)] = [
            (25, 43, "r_cellar_nw", .thetaE), (55, 43, "r_elder_door", .thetaI),
            (20, 31, "r_weaver_porch", .thetaI), (58, 31, "r_smithy_forge", .thetaI),
            (25, 19, "r_woodcutter_shed", .thetaE), (51, 19, "r_farm_gate", .thetaE),
            (40, 35, "r_town_hall_steps", .thetaI), (40, 26, "r_crossroads_south", .thetaE),
            (32, 29, "r_west_bridge", .thetaE), (48, 29, "r_east_crossing", .thetaI),
            (28, 42, "r_north_hedge_gap", .thetaE), (52, 42, "r_north_lane", .thetaE),
            (16, 29, "r_deep_west_path", .thetaE), (64, 29, "r_deep_east_path", .thetaE),
            (40, 47, "r_north_clearing_edge", .thetaE), (40, 13, "r_south_mill_gate", .thetaE),
            (24, 25, "r_orchard_corner", .thetaI), (56, 25, "r_pond_pier", .thetaI),
            (36, 42, "r_hall_backdoor", .thetaI), (44, 42, "r_hall_cellar", .thetaE),
            (30, 20, "r_woodland_track", .thetaE), (50, 20, "r_pasture_stile", .thetaE),
            (38, 30, "r_well_square", .thetaI), (42, 30, "r_fountain_side", .thetaI),
            (18, 40, "r_northwest_meadow_trail", .thetaE), (62, 40, "r_northeast_meadow_trail", .thetaE),
            (18, 15, "r_southwest_forest_path", .thetaE), (62, 15, "r_southeast_lakeside", .thetaE),
            (35, 27, "r_peddler_stand", .thetaE), (45, 27, "r_lantern_rack", .thetaI),
        ]
        return configs.enumerated().map { index, cfg in
            DecisionLocation(
                id: index,
                position: CGPoint(x: CGFloat(cfg.x) * Self.tileSize, y: CGFloat(cfg.y) * Self.tileSize),
                regionName: cfg.name,
                trait: cfg.trait
            )
        }
    }

    private func placeGroundTile(col: Int, row: Int, tile: TileType, in node: SKNode, code: Int) {
        setGround(col, row, tile, code: code)
        _ = node
    }

    private func placeStaticCollider(col: Int, row: Int, tile: TileType, in node: SKNode) {
        let assets = VillageAssets.shared
        let pos = CGPoint(x: CGFloat(col) * Self.tileSize + Self.tileSize / 2, y: CGFloat(row) * Self.tileSize + Self.tileSize / 2)
        let sprite = SKSpriteNode(texture: assets.texture(for: tile), size: CGSize(width: Self.tileSize, height: Self.tileSize))
        sprite.position = pos
        sprite.zPosition = 6
        node.addChild(sprite)
        grid[row][col] = 2

        let collider = SKNode()
        collider.position = pos
        let body = SKPhysicsBody(rectangleOf: CGSize(width: Self.tileSize, height: Self.tileSize))
        body.isDynamic = false
        body.categoryBitMask = PhysicsCategory.boundary
        body.collisionBitMask = PhysicsCategory.player
        collider.physicsBody = body
        node.addChild(collider)
    }

    public func regionName(for position: CGPoint) -> String {
        let col = max(0, min(Self.mapCols - 1, Int(position.x / Self.tileSize)))
        let row = max(0, min(Self.mapRows - 1, Int(position.y / Self.tileSize)))

        if col < 25 && row > 40 { return "r_northwest_woods" }
        if col > 55 && row > 40 { return "r_northeast_woods" }
        if col < 25 && row < 20 { return "r_southwest_meadow" }
        if col > 55 && row < 20 { return "r_southeast_pond" }
        if col >= 35 && col <= 45 && row >= 25 && row <= 35 { return "r_village_square" }
        return "r_\(col)_\(row)"
    }
}
