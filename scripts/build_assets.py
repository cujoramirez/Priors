"""Generate the game-ready art from the CC0 source packs.

Run: python3 scripts/build_assets.py

Everything the app draws is produced here from `Priors/Assets-source/`, so the
mapping from source pixels to shipped texture is auditable and re-runnable
rather than a hand-pasted atlas nobody can regenerate. The previous
`VillageTiles.png` was hand-assembled: its content did not sit on the grid the
code sliced, so `wallStone` was a window and `well` was a beehive.

Sources, both CC0 (Creative Commons Zero), both Kenney:
  - Tiles      : "Tiny Town" 1.1            — kenney-tiny-town/License.txt
  - Characters : "Roguelike Characters" 2.0 — kenney-roguelike-characters/License.txt

Tiny Town is a buildings-and-props pack and contains no people: its tile 104,
which an earlier version of this script shipped as the player, is a **well** —
shingled roof, wooden posts, blue water, stone base. It sits between a ladder, a
bomb, a barrel and a bucket. The whole village was populated by walking wells.
Characters now come from the Roguelike Characters pack, where columns 0 and 1
hold finished figures and columns 2+ are paperdoll layers.

Everything is 16x16 native. The app renders at 2x for 32pt tiles.
"""
from __future__ import annotations

import pathlib
import shutil
import json
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "Priors/Assets-source/kenney-tiny-town/Tilemap/tilemap_packed.png"
CHARS = ROOT / "Priors/Assets-source/kenney-roguelike-characters/Spritesheet/roguelikeChar_transparent.png"
CHAR_TILE = 16
CHAR_PITCH = 17        # 16px tiles with 1px spacing
XCASSETS = ROOT / "Priors/Priors/Priors/Assets.xcassets"
RESOURCES = ROOT / "Priors/Priors/Priors/Resources"

TILE = 16
SHEET_COLS = 12

#: Row/column of each finished figure in the Roguelike Characters sheet.
#: Columns 0 and 1 are complete characters; verified by rendering the grid, not
#: assumed. The player is a plain villager — SPEC §2.4 allows no named
#: protagonist and no personality, so it is deliberately unremarkable.
PLAYER_CELL = (7, 0)
VILLAGER_CELLS = [(8, 0), (5, 1), (9, 1)]

def sheet() -> Image.Image:
    return Image.open(SRC).convert("RGBA")


def tile(sheet_img: Image.Image, index: int) -> Image.Image:
    r, c = divmod(index, SHEET_COLS)
    return sheet_img.crop((c * TILE, r * TILE, c * TILE + TILE, r * TILE + TILE))


def key_out(img: Image.Image, colour) -> Image.Image:
    out = img.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            if px[x, y] == colour:
                px[x, y] = (0, 0, 0, 0)
    return out


def recolour(img: Image.Image, mapping: dict) -> Image.Image:
    out = img.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            if px[x, y] in mapping:
                px[x, y] = mapping[px[x, y]]
    return out


def char(row: int, col: int) -> Image.Image:
    sheet_img = Image.open(CHARS).convert("RGBA")
    x, y = col * CHAR_PITCH, row * CHAR_PITCH
    return sheet_img.crop((x, y, x + CHAR_TILE, y + CHAR_TILE))


def _dominant(img: Image.Image, xs, ys):
    from collections import Counter
    px = img.load()
    c = Counter(px[x, y] for y in ys for x in xs if px[x, y][3])
    return c.most_common(1)[0][0] if c else None


def strip_face(img: Image.Image) -> Image.Image:
    """Remove eyes and mouth. SPEC §8: "Villagers have no faces. Faces invite
    role-play."

    The face is whatever sits *inside* the head band with skin on both sides of
    it — eyes at the two darker pixels of the eye row, and the mouth below them.
    Detecting it by enclosure rather than by fixed coordinates means one rule
    covers every figure in the pack, whose faces sit at slightly different rows.
    """
    out = img.copy()
    px = out.load()
    skin = _dominant(out, range(5, 11), range(3, 9))
    if skin is None:
        return out
    for y in range(3, 9):
        for x in range(5, 11):
            if px[x, y][3] == 0 or px[x, y] == skin:
                continue
            left = any(px[xx, y] == skin for xx in range(max(0, x - 2), x))
            right = any(px[xx, y] == skin for xx in range(x + 1, min(CHAR_TILE, x + 3)))
            if left and right:
                px[x, y] = skin
    return out


def back_of_head(img: Image.Image) -> Image.Image:
    """Seen from behind: hair covers the face."""
    out = img.copy()
    px = out.load()
    skin = _dominant(out, range(5, 11), range(3, 9))
    hair = _dominant(out, range(4, 12), range(1, 3))
    if skin is None or hair is None or hair == skin:
        return strip_face(out)
    for y in range(2, 9):
        for x in range(4, 12):
            if px[x, y] == skin:
                px[x, y] = hair
    return strip_face(out)


def bob(img: Image.Image) -> Image.Image:
    """Second walk frame: the whole figure lifts one pixel.

    A one-pixel bounce is the readable walk cue at this scale. The pack has a
    single character pose, so an animated cycle has to be derived rather than
    sliced — the previous code sliced a four-direction cycle out of a sheet that
    never contained one.
    """
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.alpha_composite(img, (0, -1))
    return out


def back_view(img: Image.Image) -> Image.Image:
    """Seen from behind: hair covers the head, and the tabard is not visible."""
    out = img.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            p = px[x, y]
            if y <= 5 and p in (SKIN, SKIN_ARM):
                px[x, y] = HAIR_DARK
            elif p in (TABARD, TABARD_HI):
                px[x, y] = BODY
    return out


def imageset(name: str, img: Image.Image) -> None:
    d = XCASSETS / f"{name}.imageset"
    d.mkdir(parents=True, exist_ok=True)
    img.save(d / f"{name}.png")
    (d / "Contents.json").write_text(json.dumps({
        "images": [{"filename": f"{name}.png", "idiom": "universal", "scale": "1x"},
                   {"idiom": "universal", "scale": "2x"},
                   {"idiom": "universal", "scale": "3x"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"preserves-vector-representation": False},
    }, indent=2))
    RESOURCES.mkdir(parents=True, exist_ok=True)
    img.save(RESOURCES / f"{name}.png")
    print(f"  {name}.png  {img.size[0]}x{img.size[1]}")


#: Kenney's outline colour, reused so generated tiles sit in the same palette.
OUTLINE = (61, 33, 45, 255)
WATER_DEEP = (0, 120, 178, 255)
WATER_MID = (0, 154, 220, 255)
WATER_HI = (118, 228, 255, 255)
GRASS = (106, 190, 88, 255)


def extras_row(width: int) -> Image.Image:
    """Tiles Tiny Town does not contain, drawn in its palette.

    Only water. The village has a pond, and `r_southeast_pond` is what COPY R7
    renders as "the pond" — dropping the water would make a landmark the report
    names stop existing. Generating it is cheaper than making the report lie.
    """
    row = Image.new("RGBA", (width, TILE), (0, 0, 0, 0))
    d = Image.new("RGBA", (TILE, TILE), WATER_MID)
    px = d.load()
    for (x, y) in ((3, 4), (4, 4), (10, 6), (11, 6), (5, 11), (6, 11), (12, 12)):
        px[x, y] = WATER_HI
    for (x, y) in ((8, 2), (2, 9), (13, 9), (9, 13)):
        px[x, y] = WATER_DEEP
    row.alpha_composite(d, (0, 0))                       # index 132: water

    e = d.copy()
    ep = e.load()
    for x in range(TILE):
        ep[x, 0] = GRASS
        ep[x, 1] = GRASS if x % 3 else OUTLINE
    row.alpha_composite(e, (TILE, 0))                    # index 133: water edge
    return row


def main() -> None:
    s = sheet()
    print("building assets from Kenney Tiny Town (CC0)")

    # 1. The tile sheet plus one generated row. Slicing happens in Swift at 16px
    #    with an index map, so there is no second place for the grid to go wrong.
    tiles = Image.new("RGBA", (s.width, s.height + TILE), (0, 0, 0, 0))
    tiles.alpha_composite(s, (0, 0))
    tiles.alpha_composite(extras_row(s.width), (0, s.height))
    imageset("TinyTown", tiles)

    # 2. Character atlas: 4 columns x 3 rows of 16x16.
    #    row 0: player down A/B, player side A/B
    #    row 1: player up A/B,   villager 1 A/B
    #    row 2: villager 2 A/B,  villager 3 A/B
    #
    # The pack has no walk cycle and no back view, so both are derived: a
    # one-pixel bob for the step, hair over the face for the back. Left is the
    # side pair mirrored at draw time.
    player = char(*PLAYER_CELL)
    up = back_of_head(player)
    villagers = [strip_face(char(r, c)) for r, c in VILLAGER_CELLS]

    frames = [player, bob(player), player, bob(player),
              up, bob(up), villagers[0], bob(villagers[0]),
              villagers[1], bob(villagers[1]), villagers[2], bob(villagers[2])]

    atlas = Image.new("RGBA", (4 * TILE, 3 * TILE), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        atlas.alpha_composite(f, ((i % 4) * TILE, (i // 4) * TILE))
    imageset("Traveller", atlas)

    # 3. Retire the hand-pasted atlas and the character base it never matched.
    for stale in ("VillageTiles", "rpgbase_clean", "ClassicRPG_Sheet"):
        d = XCASSETS / f"{stale}.imageset"
        if d.exists():
            shutil.rmtree(d)
            print(f"  removed stale imageset {stale}")
        p = RESOURCES / f"{stale}.png"
        if p.exists():
            p.unlink()
            print(f"  removed stale resource {stale}.png")


if __name__ == "__main__":
    main()
