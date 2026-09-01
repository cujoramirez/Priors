# Asset Survey: 32×32 Top-Down Village Game

This survey evaluates free, top-down pixel-art asset packs suitable for building a 32×32 village game. Per the design specification, the game requires:
1. **Terrain / ground tiles** (grass, paths, dirt, water edges, elevation).
2. **Houses / buildings** (village roofs, walls, doors, chimneys, props).
3. **Player character** with 4-direction walk animations.
4. **Villagers** (NPC sprites).
5. **Faceless design requirement**: The game's aesthetic requires faceless villagers. Asset packs with existing facial features require sprite editing to remove eyes/mouths.

---

## Asset Comparison Table

| Pack Name | Source URL | Category | Licence | Native Tile Size | Commercial Use | Attribution Required | Sprites Have Faces? (Editing Effort) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Kenney • Tiny Town** | [kenney.nl/assets/tiny-town](https://kenney.nl/assets/tiny-town) | Terrain, Buildings, Props | **CC0 1.0 Universal** (Public Domain) | 16×16 (integer scales to 32×32) | **Yes** | **No** | **N/A** (Tile & building props only) |
| **Kenney • Roguelike Characters** | [kenney.nl/assets/roguelike-characters](https://kenney.nl/assets/roguelike-characters) | Villagers, NPCs | **CC0 1.0 Universal** (Public Domain) | 16×16 (integer scales to 32×32) | **Yes** | **No** | **Minimal / Faceless** (Minimal 1-pixel eyes or silhouette hoods; trivial 10-second erase per sprite) |
| **Kenney • Roguelike Modern / City** | [kenney.nl/assets/roguelike-city](https://kenney.nl/assets/roguelike-city) | Terrain, Buildings, Interiors | **CC0 1.0 Universal** (Public Domain) | 16×16 (integer scales to 32×32) | **Yes** | **No** | **N/A** (Environment only) |
| **Dungeon Crawl Stone Soup (DCSS) 32×32 Tiles** | [opengameart.org/content/dungeon-crawl-32x32-tiles](https://opengameart.org/content/dungeon-crawl-32x32-tiles) | Terrain, Buildings, Monsters, NPCs | **CC0 1.0 Universal** (Public Domain) | 32×32 | **Yes** | **No** | **Mixed** (Static 32×32 portraits/sprites; humanoids have faces requiring editing; no 4-dir walk anims) |
| **OGA • 32×32 Top-Down Town & Buildings** (by ArMM1998 / Clint Bellanger) | [opengameart.org/content/town-tiles](https://opengameart.org/content/town-tiles) | Buildings, Houses, Roofs | **CC0 1.0 Universal** (Public Domain) | 32×32 | **Yes** | **No** | **N/A** (Structures and architecture only) |
| **OGA • 32×32 Faceless Character Base Spritesheets** (by Stephen Challener / Redshrike & Johannes Sjölund) | [opengameart.org/content/16x16-16x24-32x32-character-sprite-sheet](https://opengameart.org/content/16x16-16x24-32x32-character-sprite-sheet) | Player Character, Villager Bases | **CC0 1.0 Universal** (Public Domain) | 32×32 | **Yes** | **No** | **No faces** (Featureless humanoid mannequins with 4-direction 3/4-frame walk cycles; **zero editing effort**) |
| **OGA • 32×32 Village & Overworld Tileset** (by Daniel Cook / Lostgarden via OGA) | [opengameart.org/content/classic-rpg-tileset](https://opengameart.org/content/classic-rpg-tileset) | Terrain, Foliage, Village Props | **CC0 1.0 Universal** (Public Domain) | 32×32 | **Yes** | **No** | **N/A** (Environment and structures only) |
| **Pipoya • Free RPG Character Sprites 32×32** | [pipoya.itch.io/pipoya-free-rpg-character-sprites-32x32](https://pipoya.itch.io/pipoya-free-rpg-character-sprites-32x32) | Player Character, Villagers (4-dir walk anims) | **itch.io Custom**: *"Free for commercial and non-commercial game projects. Modification allowed. Redistribution of the asset itself is prohibited."* | 32×32 | **Yes** | **No** (Optional/appreciated) | **Yes** (Anime-style 2-pixel eyes; requires erasing 2–4 face pixels across 12 frames per character = ~2 min per villager) |
| **Cup Nooble • Sprout Lands** | [cupnooble.itch.io/sprout-lands-asset-pack](https://cupnooble.itch.io/sprout-lands-asset-pack) | Terrain, Houses, Player, NPCs, Props | **itch.io Custom**: *"You can use these assets in any commercial or non commercial project. You may modify the design. You can not distribute or resell the assets on their own."* | 16×16 (integer scales cleanly to 32×32) | **Yes** | **No** (Optional/appreciated) | **Yes** (Simple dot eyes; 1-pixel erasure per frame across 4 directions = ~30s per character) |
| **Super Retro World • Exterior Pack** (by Gif_VGC) | [gif-vgc.itch.io/super-retro-world-exterior-pack](https://gif-vgc.itch.io/super-retro-world-exterior-pack) | Terrain, Village Houses, Nature | **itch.io Custom**: *"You are free to use this asset in any kind of project (commercial or not). You can modify it. You may not resell or redistribute."* | 16×16 (scalable to 32×32) | **Yes** | **No** (Appreciated) | **N/A** (Environment tileset only) |

---

## Detailed Notes & Recommendations

### 1. Zero-Friction CC0 Composition (Recommended)
- **Environment & Buildings**: Combine **OGA 32×32 Town & Buildings** and **Daniel Cook's 32×32 Village Tiles** with **Kenney Tiny Town** (scaled 2× nearest-neighbour). All are 100% CC0, requiring zero attribution and zero legal overhead.
- **Player & Villagers**: Use **Stephen Challener's CC0 32×32 Faceless Character Base Spritesheet**.
  - Provides native 32×32 pixel mannequins with complete 4-direction, 4-frame walk cycles (Down, Up, Left, Right).
  - Crucially, sprites are inherently **faceless / featureless**, matching the design requirement with **zero editing effort**. Clothes and color variations can be layered on top of the base template without needing to erase eyes or mouths.

### 2. Alternative: Pipoya 32×32 Character Pack (itch.io)
- Provides 8+ distinct villager variations with full 4-direction 3-frame walk cycles formatted natively at 32×32.
- Licence permits unrestricted commercial use without mandatory attribution.
- **Editing overhead**: Each character has distinct 2-pixel colored eyes. Erasing these pixels across 12 frames (3 frames × 4 directions) takes roughly 1–2 minutes per character in Aseprite or Photoshop.

### 3. Scaling 16×16 Assets to 32×32
- 16×16 pixel art (such as Kenney Tiny Town and Cup Nooble Sprout Lands) scales to 32×32 with a 200% nearest-neighbour (point sampling) resize with zero blur, remaining visually sharp and matching the SpriteKit pixel-art texture filtering mode (`SKTextureFilteringMode.nearest`).

---

## 4. Acquired CC0 Asset Packs & File Paths

Per Task `T4.1`, the CC0 packs have been downloaded to `Priors/Assets-source/` with their respective `LICENSE` files:

| Pack Name | Downloaded Path | Key Files / Subdirectories | Licence File |
| :--- | :--- | :--- | :--- |
| **Kenney Tiny Town** | `Priors/Assets-source/kenney-tiny-town/` | `Tiles/`, `Tilemap/`, `Sample.png`, `Preview.png` | `License.txt` (CC0 1.0) |
| **Kenney Roguelike Characters** | `Priors/Assets-source/kenney-roguelike-characters/` | `Spritesheet/`, `Preview.png`, `Sample.png` | `License.txt` (CC0 1.0) |
| **Kenney Roguelike Modern City** | `Priors/Assets-source/kenney-roguelike-modern-city/` | `Tiles/`, `Tilemap/`, `Preview.png`, `Sample.png` | `License.txt` (CC0 1.0) |
| **OGA 32×32 Town & Buildings** | `Priors/Assets-source/oga-town-tiles/` | `town_tiles.png`, `town_tiles_preview.png` | `LICENSE` (CC0 1.0) |
| **OGA 32×32 Village & Overworld** | `Priors/Assets-source/oga-classic-rpg-tileset/` | `ClassicRPGTileset/` (tiles, trees, roofs) | `LICENSE` (CC0 1.0) |
| **DCSS 32×32 Tiles** | `Priors/Assets-source/dcss-32x32-tiles/` | `crawl-tiles Oct-5-2010/` | `LICENSE` (CC0 1.0) |
| **OGA Faceless Character Bases** | `Priors/Assets-source/oga-character-bases/` | `rpgbaseformatted.png`, `rpgbaseprev.png` | `LICENSE` (CC0 1.0) |

*Note: All downloaded files remain untouched in raw source format under `Priors/Assets-source/` and have not been imported into `Assets.xcassets`.*

