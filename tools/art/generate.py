"""Pixel art for Kingdom Tiles (GDD §13): tiles, buildings, level badges, resource icons and the
wood + paper UI frames. Everything is drawn here from code, so running the script again redraws
the whole set with the same palette. Hand-drawn PNGs can replace any output file (same name).

Run from the project folder:  python tools/art/generate.py
Needs Pillow. Writes into assets/. Board art is drawn at its pixel size (24×24 tiles, 16×16 buildings) and the game
scales it ×2 with nearest filtering; icons and UI frames are written already scaled ×2.
"""

import random

from pixel import ASSETS, CLEAR, P, UI_SCALE, Canvas, hex_color, speckle, speckle_area
import battle_art
import item_art
import portrait_art
import world_art
import map_art


# --- Tiles (24×24, seamless, no outline) -------------------------------------------------------
# Cells are 48 px on screen (M13c): tiles are drawn at 24×24 so their pixels match the ×2 buildings,
# which stand in the middle of the cell with room around them for the walkers.

TILE = 24


def tile_grass(seed: int = 1) -> Canvas:
    rng = random.Random(seed)
    c = Canvas(TILE, TILE, P["grass"])
    speckle(c, rng, [P["grass_dark"], P["grass_light"]], 50)
    for _ in range(6):  # small tufts
        x, y = rng.randrange(1, TILE - 3), rng.randrange(2, TILE - 1)
        c.px(x, y, P["grass_dark"])
        c.px(x + 1, y - 1, P["grass_dark"])
        c.px(x + 2, y, P["grass_dark"])
    return c


def tile_farmland() -> Canvas:
    """A rice paddy: raised earth bund around water with rows of rice."""
    c = Canvas(TILE, TILE, P["paddy_water"])
    c.rect(1, 1, TILE - 2, TILE - 2, P["paddy"])
    for y in range(2, TILE - 1, 3):
        for x in range(2, TILE - 1, 2):
            c.px(x, y, P["paddy_dark"])
            c.px(x, y - 1, P["grass_light"])
    c.hline(0, TILE - 1, 0, P["bund"])
    c.vline(0, 0, TILE - 1, P["bund"])
    c.hline(0, TILE - 1, TILE - 1, P["bund_dark"])
    c.vline(TILE - 1, 0, TILE - 1, P["bund_dark"])
    for x, y in ((6, 4), (15, 9), (9, 16), (18, 19)):
        c.px(x, y, P["paddy_water"])
    return c


def tree(c: Canvas, x: int, y: int) -> None:
    """A round canopy 7px wide with its trunk; (x, y) is the canopy's top-left."""
    shape = Canvas(9, 9)
    shape.ellipse(4.5, 3.6, 3.6, 3.4, P["leaf"])
    shape.vline(4, 6, 8, P["trunk"])
    shape.px(3, 1, P["leaf_light"])
    shape.px(2, 2, P["leaf_light"])
    shape.px(3, 2, P["leaf_light"])
    shape.px(5, 5, P["leaf_dark"])
    shape.px(6, 4, P["leaf_dark"])
    shape.outline(P["leaf_dark"])
    c.paste(shape, x - 1, y - 1) if x >= 1 and y >= 1 else _paste_clipped(c, shape, x - 1, y - 1)


def _paste_clipped(c: Canvas, shape: Canvas, x: int, y: int) -> None:
    for yy in range(shape.height):
        for xx in range(shape.width):
            color = shape.get(xx, yy)
            if color[3] and 0 <= x + xx < c.width and 0 <= y + yy < c.height:
                c.px(x + xx, y + yy, color)


def tile_forest() -> Canvas:
    rng = random.Random(7)
    c = Canvas(TILE, TILE, P["grass_dark"])
    speckle(c, rng, [P["leaf_dark"], P["grass"]], 36)
    for x, y in ((1, 0), (9, -1), (17, 1), (5, 7), (13, 8), (20, 10), (-2, 11), (8, 15), (16, 16), (1, 17)):
        tree(c, x, y)
    return c


def rock(c: Canvas, x: int, y: int, w: int, h: int) -> None:
    shape = Canvas(w + 2, h + 2)
    shape.ellipse((w + 2) / 2, (h + 2) / 2 + 0.4, w / 2, h / 2, P["rock"])
    for yy in range(shape.height):
        for xx in range(shape.width):
            if shape.get(xx, yy)[3] and yy > (h + 2) * 0.62:
                shape.px(xx, yy, P["rock_dark"])
    shape.px(2, 2, P["rock_light"])
    shape.px(3, 2, P["rock_light"])
    shape.px(2, 3, P["rock_light"])
    shape.outline()
    c.paste(shape, x - 1, y - 1)


def tile_hill() -> Canvas:
    rng = random.Random(3)
    c = Canvas(TILE, TILE, P["grass"])
    speckle(c, rng, [P["grass_dark"], P["grass_light"]], 30)
    rock(c, 3, 4, 13, 10)
    rock(c, 14, 13, 8, 7)
    rock(c, 2, 16, 6, 4)
    return c


def tile_wild() -> Canvas:
    rng = random.Random(5)
    c = Canvas(TILE, TILE, P["wild"])
    speckle(c, rng, [P["wild_dot"], P["wild_dark"]], 58)
    return c


def key_frame() -> Canvas:
    """Drawn over key cells, above buildings, so ×2 cells stay visible: thick gold corner brackets
    and a small diamond in the top-left corner."""
    c = Canvas(TILE, TILE)
    last = TILE - 1
    for x0, y0, dx, dy in ((0, 0, 1, 1), (last, 0, -1, 1), (0, last, 1, -1), (last, last, -1, -1)):
        for d in range(6):
            for w in range(2):
                c.px(x0 + dx * d, y0 + dy * w, P["gold"])
                c.px(x0 + dx * w, y0 + dy * d, P["gold"])
        c.px(x0, y0, P["gold_light"])
    for dy in range(-2, 3):  # mini diamond centered at (5, 5)
        half = 2 - abs(dy)
        c.hline(5 - half, 5 + half, 5 + dy, P["gold_light"] if dy < 0 else P["gold"])
    c.outline()
    return c


def key_marker() -> Canvas:
    """Gold diamond for key cells (◆), drawn over the tile."""
    c = Canvas(TILE, TILE)
    m = TILE // 2
    for dy in range(-3, 4):
        half = 3 - abs(dy)
        c.hline(m - half - 1, m + half - 1, m + dy - 1, P["gold"])
    c.px(m - 2, m - 2, P["gold_light"])
    c.px(m - 1, m - 3, P["gold_light"])
    c.px(m - 1, m - 2, P["gold_light"])
    c.px(m, m + 1, P["gold_dark"])
    c.px(m - 1, m + 2, P["gold_dark"])
    c.outline()
    return c


# --- Buildings (transparent, outlined) ----------------------------------------------------------
# Each building also has an idle loop of ANIM_FRAMES frames (M13c), saved as "<id>_anim.png"; frame 0
# is the still picture.

ANIM_FRAMES = 4
SMOKE = hex_color("ece8e0", 225)
SMOKE_DARK = hex_color("c8c2b8", 200)


def smoke_puffs(c: Canvas, x: int, y: int, frame: int) -> None:
    """Two puffs rising from (x, y) and drifting right, one loop over ANIM_FRAMES frames. Drawn after
    the outline so the smoke stays soft."""
    for i in range(2):
        k = (frame + 2 * i) % ANIM_FRAMES
        yy = y - k
        if yy < 0:
            continue
        c.px(x + k // 2, yy, SMOKE if k < 3 else SMOKE_DARK)
        if k >= 2:
            c.px(x + k // 2 + 1, yy, SMOKE_DARK)


def anim_strip(draw) -> Canvas:
    first = draw(0)
    out = Canvas(first.width * ANIM_FRAMES, first.height)
    for f in range(ANIM_FRAMES):
        out.paste(draw(f) if f else first, f * first.width, 0)
    return out



def curved_roof(c: Canvas, x: int, y: int, w: int, h: int) -> None:
    """East Asian roof: tiled, wider at the eaves, eave tips curling up."""
    for row in range(h):
        inset = (h - 1 - row)
        color = P["roof"] if row < h - 1 else P["roof_dark"]
        c.hline(x + inset, x + w - 1 - inset, y + row, color)
    c.hline(x + h - 1, x + w - h, y, P["roof_light"])
    c.px(x - 1, y + h - 2, P["roof_dark"])
    c.px(x + w, y + h - 2, P["roof_dark"])
    for col in range(x + h, x + w - h, 2):
        c.px(col, y + 1, P["roof_dark"]) if h > 2 else None


def crenels(c: Canvas, x0: int, x1: int, y: int) -> None:
    """Battlements along the top of a wall: a merlon every other pixel pair."""
    for x in range(x0, x1 + 1):
        if (x - x0) % 3 != 2:
            c.px(x, y, P["stone_light"])


def tower(c: Canvas, x: int, y: int, level: int) -> None:
    """A 7×8 corner tower; roofed from castle level 4, gold-tipped at level 6."""
    c.rect(x, y + 2, 7, 6, P["stone_dark"])
    c.rect(x + 1, y + 2, 5, 5, P["stone"])
    c.px(x + 3, y + 4, P["door"])
    if level >= 4:
        for row in range(3):
            c.hline(x + 2 - row, x + 4 + row, y - 1 + row, P["roof"] if row < 2 else P["roof_dark"])
        c.px(x + 3, y - 2, P["gold"] if level >= 6 else P["roof_light"])
    else:
        crenels(c, x, x + 6, y + 1)


def castle(level: int, frame: int = 0) -> Canvas:
    """A walled fortress filling the 2×2 castle footprint (32×32): stone walls with battlements,
    four corner towers and a gate around a courtyard, and a keep in the middle that gains roof
    tiers, banners and gold trim with the castle level."""
    rng = random.Random(level)
    c = Canvas(32, 32)
    # Courtyard.
    c.rect(3, 8, 26, 17, P["courtyard"])
    speckle_area(c, rng, 4, 9, 27, 23, P["courtyard_dark"], 30)
    # Back and side walls (seen from above), front wall (seen from the front, taller).
    c.rect(2, 6, 28, 3, P["stone"])
    crenels(c, 2, 29, 5)
    c.rect(1, 6, 3, 19, P["stone"])
    c.rect(28, 6, 3, 19, P["stone"])
    c.vline(3, 8, 23, P["stone_dark"])
    c.vline(28, 8, 23, P["stone_dark"])
    c.rect(1, 24, 30, 7, P["stone"])
    for y in (26, 28):
        for x in range(2 + (y // 2) % 2 * 2, 30, 4):
            c.hline(x, x + 2, y, P["stone_dark"])
    c.hline(1, 30, 30, P["stone_dark"])
    crenels(c, 1, 30, 23)
    # Gate.
    c.rect(13, 25, 6, 6, P["door"])
    c.hline(14, 17, 24, P["door"])
    c.vline(16, 26, 30, P["wood_dark"])
    # Keep: tiers 1, 1, 2, 2, 3, 3 by castle level.
    tiers = (level + 1) // 2
    width, base = 18, 21
    top = base
    for tier in range(tiers):
        left = 16 - width // 2
        wall_h = 4 if tier == 0 else 3
        c.rect(left + 2, top - wall_h + 1, width - 4, wall_h, P["wall"])
        c.hline(left + 2, left + width - 3, top, P["wall_shade"])
        if tier == 0:
            c.rect(15, top - 2, 2, 3, P["door"])
            c.px(left + 4, top - 2, P["door"])
            c.px(left + width - 5, top - 2, P["door"])
        else:
            c.px(16, top - 1, P["door"])
        top -= wall_h + 3
        curved_roof(c, left, top + 1, width, 3)
        width -= 4
    # Corner towers over the walls.
    for x, y in ((0, 3), (25, 3), (0, 20), (25, 20)):
        tower(c, x, y, level)
    wave = frame % 2  # banners flutter: a dip in the middle on odd frames
    if level >= 2:  # banner on the keep
        c.vline(16, top - 4, top, P["wood_dark"])
        c.rect(17, top - 4, 3, 2, P["red"])
        if wave:
            c.px(18, top - 4, CLEAR)
            c.px(18, top - 2, P["red"])
    if level >= 5:  # banners on the front towers
        for x in (3, 28):
            c.vline(x, 14, 18, P["wood_dark"])
            left = x + 1 if x < 16 else x - 3
            c.rect(left, 14, 3, 2, P["red"])
            if wave:
                c.px(left + 1, 14, CLEAR)
                c.px(left + 1, 16, P["red"])
    if level >= 6:  # gold trim on every roof ridge
        for y in range(c.height):
            for x in range(c.width):
                if c.get(x, y) == P["roof_light"]:
                    c.px(x, y, P["gold"])
    c.outline()
    return c


def hall(roof: str, roof_dark: str, wall_w: int = 12) -> Canvas:
    c = Canvas(16, 16)
    left = (16 - wall_w) // 2
    c.rect(left, 8, wall_w, 6, P["wall"])
    c.hline(left, left + wall_w - 1, 13, P["wall_shade"])
    for row in range(4):
        inset = 3 - row
        c.hline(left - 1 + inset, left + wall_w - inset, 4 + row, P[roof] if row < 3 else P[roof_dark])
    c.px(left - 2, 6, P[roof_dark])
    c.px(left + wall_w + 1, 6, P[roof_dark])
    return c


def barracks(frame: int = 0) -> Canvas:
    c = hall("red", "red_dark", 12)
    c.rect(7, 10, 3, 4, P["door"])
    c.rect(4, 10, 2, 2, P["door"])
    c.rect(11, 10, 2, 2, P["door"])
    c.vline(14, 2, 13, P["wood_dark"])  # spear by the door
    c.px(14, 1, P["rock_light"])
    c.rect(1, 3, 1, 10, P["wood_dark"])  # banner pole
    c.rect(2, 3, 3, 3, P["roof"])
    if frame % 2:  # the banner flutters
        c.px(4, 3, CLEAR)
        c.px(4, 6, P["roof"])
    c.outline()
    return c


def watchtower(frame: int = 0) -> Canvas:
    c = Canvas(16, 16)
    for x in (5, 10):
        c.vline(x, 6, 14, P["wood_dark"])
    for y in (9, 12):
        c.hline(5, 10, y, P["wood"])
    c.px(7, 10, P["wood"])
    c.px(8, 11, P["wood"])
    c.rect(4, 5, 8, 2, P["wood"])
    c.rect(5, 3, 6, 2, P["wall"])
    for row in range(3):
        c.hline(3 + 2 - row, 12 - 2 + row, row, P["red"] if row < 2 else P["red_dark"])
    c.px(7, 3, P["door"])
    c.outline()
    # A lamp flickers in the lookout.
    c.px(7, 3, (P["gold"], P["gold_light"], P["gold"], P["red_light"])[frame])
    return c


def farm(frame: int = 0) -> Canvas:
    c = Canvas(16, 16)
    c.rect(2, 9, 9, 5, P["wall"])
    c.rect(5, 10, 2, 4, P["door"])
    for row in range(5):
        inset = 4 - row
        c.hline(1 + inset, 11 - inset, 4 + row, P["thatch"] if row % 2 == 0 else P["thatch_dark"])
    c.ellipse(13, 12, 2.6, 2.6, P["thatch"])  # haystack
    c.px(12, 11, P["thatch_dark"])
    c.px(14, 13, P["thatch_dark"])
    c.vline(9, 5, 6, P["stone_dark"])  # chimney
    c.outline()
    smoke_puffs(c, 9, 3, frame)
    return c


def lumber_mill(frame: int = 0) -> Canvas:
    c = hall("wood", "wood_dark", 9)
    c.rect(5, 10, 2, 4, P["door"])
    for i, y in enumerate((11, 13)):  # log pile
        c.hline(9, 14, y, P["wood"])
        c.px(14, y, P["wood_light"])
        c.hline(9, 14, y + 1, P["wood_dark"]) if i == 1 else None
    c.px(9, 11, P["wood_light"])
    c.vline(1, 8, 13, P["rock_light"])  # saw blade leaning on the wall
    c.vline(2, 9, 12, P["rock"])
    c.outline()
    c.px(1, 8 + (frame * 2) % 6, P["white"])  # a glint runs down the blade
    if frame % 2:  # sawdust by the log pile
        c.px(10, 10, P["wood_light"])
        c.px(12, 9, P["wood_light"])
    return c


def mine(frame: int = 0) -> Canvas:
    c = Canvas(16, 16)
    c.ellipse(8, 11, 7.2, 5.6, P["rock"])
    for y in range(c.height):
        for x in range(c.width):
            if c.get(x, y)[3] and y >= 12:
                c.px(x, y, P["rock_dark"])
    c.rect(5, 9, 6, 6, P["door"])  # tunnel with timber frame
    c.vline(5, 9, 14, P["wood"])
    c.vline(10, 9, 14, P["wood"])
    c.hline(5, 10, 9, P["wood_light"])
    c.px(3, 8, P["rock_light"])
    c.px(4, 7, P["rock_light"])
    c.px(12, 12, P["ore"])
    c.px(13, 10, P["ore_light"])
    c.outline()
    # Ore glints in turn, and a lamp glows in the tunnel.
    spots = ((13, 10), (12, 12), (3, 8), (12, 12))
    c.px(*spots[frame], P["white"])
    c.px(7 + frame % 2, 12, P["gold"])
    return c


# --- Military buildings (GDD §8, M13) ------------------------------------------------------------

def war_stable(frame: int = 0) -> Canvas:
    """A long thatched stable with a horse looking out of its stall and a hay bale by the door."""
    c = Canvas(16, 16)
    c.rect(1, 8, 13, 6, P["wood"])
    c.hline(1, 13, 13, P["wood_dark"])
    for x in (1, 7, 13):
        c.vline(x, 8, 13, P["wood_dark"])
    for row in range(4):
        inset = 3 - row
        c.hline(inset, 14 - inset, 4 + row, P["thatch"] if row % 2 == 0 else P["thatch_dark"])
    c.rect(3, 9, 3, 4, P["door"])  # stall with a horse head
    bob = 1 if frame in (1, 2) else 0  # the horse nods
    c.rect(4, 9 + bob, 2, 2, P["horse"])
    c.px(5, 11 + bob if bob == 0 else 11, P["horse_dark"])
    c.px(3, 9 + bob, P["mane"])
    c.rect(9, 10, 3, 4, P["door"])
    c.hline(8, 12, 10, P["wood_light"])  # stall bar
    c.ellipse(14, 13, 1.8, 1.6, P["thatch"])
    c.px(14, 13, P["thatch_dark"])
    c.outline()
    return c


def archery_range(frame: int = 0) -> Canvas:
    """A small roofed shed and a straw target with red and white rings on a stand, an arrow in it."""
    c = Canvas(16, 16)
    c.rect(1, 9, 6, 5, P["wall"])
    c.hline(1, 6, 13, P["wall_shade"])
    for row in range(3):
        c.hline(2 - row + 1, 5 + row, 6 + row, P["red"] if row < 2 else P["red_dark"])
    c.rect(3, 10, 2, 4, P["door"])
    c.vline(11, 9, 14, P["wood_dark"])  # target stand
    c.vline(13, 10, 14, P["wood_dark"])
    c.ellipse(12, 7, 3.4, 3.4, P["thatch"])
    c.ellipse(12, 7, 2.4, 2.4, P["white"])
    c.ellipse(12, 7, 1.4, 1.4, P["red"])
    c.px(12, 7, P["gold"])
    if frame == 0:
        c.hline(8, 11, 6, P["wood_light"])  # arrow stuck in the target
        c.px(8, 5, P["white"])
    c.outline()
    if frame in (2, 3):  # the next arrow flies in from the shed
        x = 4 if frame == 2 else 6
        c.hline(x, x + 2, 6, P["wood_light"])
        c.px(x + 3, 6, P["rock_light"])
    return c


def martial_hall(frame: int = 0) -> Canvas:
    """A red-roofed training hall with a weapon rack (spear, dao, halberd) and a war banner."""
    c = hall("red", "red_dark", 10)
    c.rect(4, 10, 3, 4, P["door"])
    c.vline(10, 8, 13, P["wood_dark"])  # weapon rack
    c.vline(13, 8, 13, P["wood_dark"])
    c.hline(10, 13, 12, P["wood"])
    c.vline(11, 6, 11, P["wood_light"])
    c.px(11, 5, P["rock_light"])
    c.vline(12, 7, 11, P["wood_light"])
    c.px(12, 6, P["rock_light"])
    c.px(13, 6, P["rock_light"])
    c.vline(1, 2, 13, P["wood_dark"])  # banner
    c.rect(2, 2, 2, 4, P["gold"])
    c.px(2, 6, P["gold_dark"])
    if frame % 2:  # the banner flutters
        c.px(3, 5, CLEAR)
        c.px(4, 3, P["gold"])
    c.outline()
    return c


def military_academy(frame: int = 0) -> Canvas:
    """A two-tier blue-roofed academy with gold ridge tips and a small cannon on the yard."""
    c = Canvas(16, 16)
    c.rect(2, 8, 12, 5, P["wall"])
    c.hline(2, 13, 12, P["wall_shade"])
    curved_roof(c, 1, 5, 14, 3)
    c.rect(5, 3, 6, 2, P["wall"])
    curved_roof(c, 4, 1, 8, 2)
    c.px(8, 0, P["gold"])
    c.px(3, 6, P["gold"])
    c.px(12, 6, P["gold"])
    c.rect(7, 9, 2, 4, P["door"])
    c.px(4, 10, P["door"])
    c.px(11, 10, P["door"])
    c.rect(9, 13, 5, 1, P["rock_dark"])  # cannon on the yard
    c.px(14, 13, P["rock_dark"])
    c.ellipse(10, 14.5, 1.2, 1.2, P["wood_dark"])
    c.outline()
    c.px(8, 0, (P["gold"], P["gold_light"], P["gold"], P["gold"])[frame])
    if frame == 2:  # a practice shot from the yard cannon
        c.px(15, 12, P["gold_light"])
        c.px(15, 13, SMOKE)
    elif frame == 3:
        c.px(15, 11, SMOKE)
        c.px(14, 11, SMOKE_DARK)
    return c


# --- Administrative buildings (GDD §8, M14e) -----------------------------------------------------

def market(frame: int = 0) -> Canvas:
    """A market stall under a red and white striped awning, crates and a basket of fruit, a lantern."""
    c = Canvas(16, 16)
    c.vline(2, 6, 13, P["wood_dark"])  # stall posts
    c.vline(13, 6, 13, P["wood_dark"])
    for x in range(1, 15):  # striped awning
        color = P["red"] if (x // 2) % 2 == 0 else P["white"]
        c.vline(x, 4, 6, color)
    c.hline(1, 14, 7, P["red_dark"])
    c.rect(3, 10, 10, 3, P["wood"])  # counter
    c.hline(3, 12, 10, P["wood_light"])
    c.hline(3, 12, 12, P["wood_dark"])
    c.ellipse(5.5, 9.2, 1.4, 1.0, P["red_light"])  # fruit
    c.ellipse(8.5, 9.2, 1.4, 1.0, P["gold"])
    c.px(11, 9, P["leaf"])
    c.rect(1, 13, 3, 2, P["wood_dark"])  # crate
    c.ellipse(13.5, 13.5, 1.6, 1.3, P["thatch"])  # basket
    c.outline()
    lantern = (7, 8, 7, 6)[frame]  # the lantern sways under the awning
    c.px(lantern, 8, P["gold_light"])
    c.px(lantern, 7, P["red"])
    return c


def granary(frame: int = 0) -> Canvas:
    """A raised storehouse on stilts with a thick thatched roof, a ladder and rice sacks."""
    c = Canvas(16, 16)
    for x in (3, 6, 9, 12):
        c.vline(x, 11, 14, P["wood_dark"])  # stilts
    c.rect(2, 7, 12, 4, P["wood"])
    c.hline(2, 13, 10, P["wood_dark"])
    for x in (5, 9):
        c.vline(x, 7, 10, P["wood_dark"])
    for row in range(5):
        inset = 4 - row
        c.hline(1 + inset, 14 - inset, 2 + row, P["thatch"] if row % 2 == 0 else P["thatch_dark"])
    c.rect(7, 8, 2, 2, P["door"])
    c.vline(10, 11, 14, P["wood_light"])  # ladder
    c.px(11, 12, P["wood_light"])
    c.px(11, 14, P["wood_light"])
    c.ellipse(2.5, 13.5, 1.6, 1.4, P["rice"])  # sacks
    c.ellipse(14, 13.5, 1.4, 1.4, P["rice"])
    c.outline()
    # A sparrow hops along the roof ridge.
    c.px((5, 7, 9, 7)[frame], 1 if frame % 2 else 2, P["trunk"])
    return c


def academy(frame: int = 0) -> Canvas:
    """A scholar's hall with a curved roof, a signboard over the door and a stand of scrolls."""
    c = Canvas(16, 16)
    c.rect(2, 8, 12, 5, P["wall"])
    c.hline(2, 13, 12, P["wall_shade"])
    curved_roof(c, 1, 4, 14, 4)
    c.rect(6, 8, 4, 1, P["wood_dark"])  # signboard
    c.px(7, 8, P["gold"])
    c.px(8, 8, P["gold"])
    c.rect(7, 10, 2, 3, P["door"])
    c.px(4, 10, P["door"])
    c.px(11, 10, P["door"])
    c.rect(12, 13, 3, 2, P["wood_dark"])  # scroll stand
    c.px(12, 12, P["paper"])
    c.px(14, 12, P["paper"])
    c.hline(1, 3, 14, P["stone"])  # stone steps
    c.outline()
    # A scroll unrolls and rolls back on the stand.
    if frame in (1, 2):
        c.hline(12, 12 + frame, 11, P["paper"])
    return c


def infirmary(frame: int = 0) -> Canvas:
    """A white-walled clinic with a green roof, herbs drying on a rack and a steaming medicine pot."""
    c = Canvas(16, 16)
    c.rect(1, 8, 10, 6, P["white"])
    c.hline(1, 10, 13, P["wall_shade"])
    for row in range(4):
        inset = 3 - row
        c.hline(inset, 11 - inset, 4 + row, P["leaf"] if row < 3 else P["leaf_dark"])
    c.rect(4, 10, 3, 4, P["door"])
    c.vline(12, 8, 13, P["wood_dark"])  # herb rack
    c.vline(15, 8, 13, P["wood_dark"])
    c.hline(12, 15, 8, P["wood"])
    c.px(13, 9, P["leaf_light"])
    c.px(14, 9, P["leaf"])
    c.px(13, 10, P["leaf"])
    c.ellipse(13.5, 13.5, 1.6, 1.2, P["rock_dark"])  # medicine pot
    c.px(13, 12, P["red"])
    c.outline()
    smoke_puffs(c, 13, 11, frame)
    return c


def magistrate(frame: int = 0) -> Canvas:
    """The magistrate's hall: a wide red-roofed hall on a stone base, a gold plaque and the court drum."""
    c = Canvas(16, 16)
    c.rect(1, 13, 14, 2, P["stone"])
    c.hline(1, 14, 14, P["stone_dark"])
    c.rect(2, 8, 12, 5, P["red"])
    c.hline(2, 13, 12, P["red_dark"])
    for x in (3, 12):
        c.vline(x, 8, 12, P["red_dark"])
    curved_roof(c, 1, 4, 14, 4)
    c.rect(6, 7, 4, 1, P["gold"])  # plaque
    c.rect(7, 9, 2, 4, P["door"])
    c.ellipse(13.5, 10.5, 1.5, 1.6, P["wood"])  # court drum on its stand
    c.px(13, 10, P["red_light"])
    c.vline(14, 12, 13, P["wood_dark"])
    c.outline()
    if frame == 1:  # someone strikes the drum
        c.px(15, 9, P["gold_light"])
        c.px(15, 11, P["gold_light"])
    c.px(8, 7, (P["gold"], P["gold_light"], P["gold"], P["gold"])[frame])
    return c


def police(frame: int = 0) -> Canvas:
    """A dark watch office with a gray tiled roof, two red lanterns and a board of wanted posters."""
    c = Canvas(16, 16)
    c.rect(2, 8, 10, 6, P["wood_dark"])
    c.hline(2, 11, 13, P["wood_deep"])
    for row in range(4):
        inset = 3 - row
        c.hline(1 + inset, 12 - inset, 4 + row, P["stone_dark"] if row < 3 else P["rock_dark"])
    c.hline(4, 9, 4, P["stone"])
    c.rect(5, 10, 3, 4, P["door"])
    c.vline(13, 8, 14, P["wood"])  # notice board
    c.rect(12, 8, 4, 3, P["wood_dark"])
    c.px(12, 9, P["paper"])
    c.px(14, 9, P["paper"])
    c.px(13, 9, P["paper_shade"])
    c.outline()
    glow = (P["red_light"], P["red"], P["red_light"], P["gold_light"])
    c.px(3, 9, glow[frame])  # lanterns by the door flicker
    c.px(10, 9, glow[(frame + 2) % 4])
    return c


DIGITS = {
    1: ["010", "110", "010", "010", "111"], 2: ["110", "001", "010", "100", "111"],
    3: ["110", "001", "010", "001", "110"], 4: ["101", "101", "111", "001", "001"],
    5: ["111", "100", "110", "001", "110"], 6: ["011", "100", "110", "101", "010"],
    7: ["111", "001", "010", "010", "010"],
}


def level_badge(level: int) -> Canvas:
    """A small wooden plate with the building level in gold."""
    c = Canvas(7, 9)
    c.rect(1, 1, 5, 7, P["wood_dark"])
    for row, line in enumerate(DIGITS[level]):
        for col, bit in enumerate(line):
            if bit == "1":
                c.px(2 + col, 2 + row, P["gold"])
    c.outline()
    return c


def turns_badge(turns: int) -> Canvas:
    """A small stone plate with the turns a construction still needs, in dark ink."""
    c = Canvas(7, 9)
    c.rect(1, 1, 5, 7, P["stone_light"])
    for row, line in enumerate(DIGITS[turns]):
        for col, bit in enumerate(line):
            if bit == "1":
                c.px(2 + col, 2 + row, P["outline"])
    c.outline()
    return c


def foundation() -> Canvas:
    """A cell of a new building's foundation: packed earth, corner stones and string lines."""
    rng = random.Random(9)
    c = Canvas(TILE, TILE, P["dirt"])
    speckle(c, rng, [P["dirt_dark"], P["dirt_light"]], 60)
    far = TILE - 4
    for x, y in ((1, 1), (far, 1), (1, far), (far, far)):
        c.rect(x, y, 3, 3, P["stone"])
        c.hline(x, x + 2, y, P["stone_light"])
        c.hline(x, x + 2, y + 2, P["stone_dark"])
    c.hline(4, far - 1, 2, P["wood_light"])
    c.hline(4, far - 1, TILE - 3, P["wood_light"])
    c.vline(2, 4, far - 1, P["wood_light"])
    c.vline(TILE - 3, 4, far - 1, P["wood_light"])
    return c


def scaffold(frame: int = 0) -> Canvas:
    """Bamboo scaffolding laid over a cell under construction (transparent between the poles)."""
    c = Canvas(16, 16)
    for x in (1, 14):
        c.vline(x, 0, 15, P["wood_dark"])
        c.vline(x + 1 if x == 1 else x - 1, 0, 15, P["wood"])
    for y in (4, 11):
        c.hline(0, 15, y, P["wood_light"])
        c.hline(0, 15, y + 1, P["wood_dark"])
    for i in range(10):
        c.px(3 + i, 5 + i // 2 if i < 12 else 10, P["wood"])
    for x in (1, 2, 13, 14):
        for y in (4, 11):
            c.px(x, y, P["rope"])
    # A builder on the plank swings a hammer (M13c).
    c.rect(7, 8, 2, 3, P["red_dark"])
    c.rect(7, 6, 2, 2, hex_color("f2c9a0"))
    c.hline(6, 9, 6, P["thatch"])
    if frame % 2 == 0:
        c.vline(10, 5, 7, P["wood_dark"])
        c.px(10, 4, P["rock_dark"])
    else:
        c.hline(9, 11, 9, P["wood_dark"])
        c.px(12, 9, P["rock_dark"])
        c.px(12, 10, P["gold_light"])
    return c


# --- Resource icons (12×12, saved ×2) -----------------------------------------------------------

def icon_food() -> Canvas:
    c = Canvas(12, 12)
    c.ellipse(6, 5.6, 4.2, 3.2, P["rice"])
    c.px(4, 4, P["white"])
    c.hline(1, 10, 6, P["bowl"])
    c.hline(2, 9, 7, P["bowl"])
    c.hline(2, 9, 8, P["bowl_dark"])
    c.hline(3, 8, 9, P["bowl_dark"])
    c.hline(4, 7, 10, P["bowl_dark"])
    c.outline()
    return c


def log(c: Canvas, y: int, x0: int, x1: int, bark: str, ring: str) -> None:
    c.rect(x0, y, x1 - x0, 3, P[bark])
    c.hline(x0, x1 - 1, y, P[bark + "_light"] if bark + "_light" in P else P[bark])
    c.rect(x1, y, 2, 3, P[ring])
    c.px(x1, y + 1, P["wood_dark"])


def icon_wood() -> Canvas:
    c = Canvas(12, 12)
    log(c, 6, 1, 8, "wood", "wood_light")
    log(c, 2, 2, 9, "wood", "wood_light")
    c.outline()
    return c


def icon_hardwood() -> Canvas:
    c = Canvas(12, 12)
    log(c, 4, 1, 9, "hardwood", "hardwood_ring")
    c.px(3, 5, P["hardwood_light"])
    c.px(6, 6, P["hardwood_light"])
    c.outline()
    return c


def icon_stone() -> Canvas:
    c = Canvas(12, 12)
    c.rect(1, 6, 5, 4, P["rock"])
    c.rect(6, 6, 5, 4, P["rock_dark"])
    c.rect(3, 2, 6, 4, P["rock"])
    c.hline(3, 8, 2, P["rock_light"])
    c.hline(1, 5, 6, P["rock_light"])
    c.px(6, 7, P["rock"])
    c.outline()
    return c


def icon_ore() -> Canvas:
    c = Canvas(12, 12)
    c.ellipse(6, 7.5, 4.6, 3.2, P["rock_dark"])
    for x, h in ((4, 5), (6, 7), (8, 4)):
        c.vline(x, 9 - h, 8, P["ore"])
        c.vline(x + 1, 10 - h, 8, P["ore_dark"])
        c.px(x, 9 - h, P["ore_light"])
    c.outline()
    return c


def icon_horses() -> Canvas:
    """A horse head in profile."""
    c = Canvas(12, 12)
    c.rect(4, 2, 4, 5, P["horse"])
    c.rect(2, 5, 4, 3, P["horse"])
    c.rect(5, 7, 4, 4, P["horse"])
    c.px(2, 7, P["horse_dark"])
    c.px(5, 3, P["black"])
    c.vline(8, 2, 9, P["mane"])
    c.vline(9, 3, 9, P["mane"])
    c.px(5, 1, P["horse"])
    c.px(6, 1, P["horse_dark"])
    c.outline()
    return c


# --- UI frames (designed in art pixels, saved ×2) -----------------------------------------------

def wood_grain(c: Canvas, rng: random.Random, x0: int, y0: int, x1: int, y1: int) -> None:
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            c.px(x, y, P["wood"])
        if (y - y0) % 4 == 3:
            c.hline(x0, x1, y, P["wood_dark"])
    for _ in range((x1 - x0 + 1) * (y1 - y0 + 1) // 10):
        c.px(rng.randint(x0, x1), rng.randint(y0, y1), P["wood_light"])


def panel_paper() -> Canvas:
    """Paper with a 3px wooden frame (9-slice margin 4 art px)."""
    rng = random.Random(11)
    c = Canvas(16, 16, P["outline"])
    c.rect(1, 1, 14, 14, P["wood"])
    c.hline(1, 14, 1, P["wood_light"])
    c.vline(1, 1, 14, P["wood_light"])
    c.hline(1, 14, 14, P["wood_deep"])
    c.vline(14, 1, 14, P["wood_deep"])
    c.rect(3, 3, 10, 10, P["paper"])
    c.hline(3, 12, 3, P["paper_shade"])
    c.vline(3, 3, 12, P["paper_shade"])
    speckle_area(c, rng, 4, 4, 12, 12, P["paper_fiber"], 8)
    c.rect(2, 2, 1, 12, P["wood_dark"])
    c.rect(2, 2, 12, 1, P["wood_dark"])
    c.rect(13, 2, 1, 12, P["wood_dark"])
    c.rect(2, 13, 12, 1, P["wood_dark"])
    return c


def panel_wood() -> Canvas:
    rng = random.Random(13)
    c = Canvas(16, 16, P["outline"])
    wood_grain(c, rng, 1, 1, 14, 14)
    c.hline(1, 14, 1, P["wood_light"])
    c.hline(1, 14, 14, P["wood_deep"])
    return c


def panel_inset() -> Canvas:
    """A sunken paper area for lists and info boxes."""
    c = Canvas(8, 8, P["paper_shade"])
    c.hline(0, 7, 0, P["bund_dark"])
    c.vline(0, 0, 7, P["bund_dark"])
    c.rect(1, 1, 6, 6, P["paper_fiber"])
    return c


def button(state: str) -> Canvas:
    """Raised wooden button, 16×12, 9-slice margin 3 art px."""
    base = {"normal": "wood", "hover": "wood_light", "pressed": "wood_dark", "disabled": "wood"}[state]
    c = Canvas(16, 12, P["outline"])
    c.rect(1, 1, 14, 10, P[base])
    if state == "pressed":
        c.hline(1, 14, 1, P["wood_deep"])
    else:
        c.hline(1, 14, 1, P["wood_light"] if state != "hover" else P["thatch"])
        c.hline(1, 14, 9, P["wood_dark"])
        c.hline(1, 14, 10, P["wood_deep"])
    if state == "disabled":
        gray = Canvas(16, 12)
        for y in range(12):
            for x in range(16):
                r, g, b, a = c.get(x, y)
                v = (r + g + b) // 3
                gray.px(x, y, ((v + 90) // 2, (v + 80) // 2, (v + 70) // 2, a))
        return gray
    return c


def tab(selected: bool) -> Canvas:
    """A hanging card tab, 12×12, open at the bottom (it joins the panel below)."""
    c = Canvas(12, 12, P["outline"])
    if selected:
        c.rect(1, 1, 10, 11, P["paper"])
        c.hline(1, 10, 1, P["wood_light"])
        c.hline(1, 10, 2, P["wood"])
    else:
        c.rect(1, 1, 10, 10, P["wood_dark"])
        c.hline(1, 10, 1, P["wood"])
        c.hline(0, 11, 11, P["outline"])
    return c


# --- Requirement icons (12×12, saved ×2; RequirementView, M16c) ----------------------------------

def icon_check() -> Canvas:
    """A green tick: a requirement met."""
    c = Canvas(12, 12)
    for x, y in ((1, 6), (2, 7), (3, 8), (4, 9), (5, 8), (6, 7), (7, 6), (8, 5), (9, 4), (10, 3)):
        c.rect(x, y - 1, 1, 2, P["grass_dark"])
    for x, y in ((2, 6), (3, 7), (4, 8), (5, 7), (6, 6), (7, 5), (8, 4), (9, 3), (10, 2)):
        c.px(x, y, P["grass_light"] if "grass_light" in P else P["grass"])
    c.outline()
    return c


def icon_cross() -> Canvas:
    """A red cross: a requirement not met."""
    c = Canvas(12, 12)
    for i in range(2, 10):
        c.rect(i, i, 1, 2, P["red"])
        c.rect(i, 11 - i - 1, 1, 2, P["red"])
    for i in range(3, 9):
        c.px(i, i, P["red_light"] if "red_light" in P else P["red"])
    c.outline()
    return c


def icon_gain() -> Canvas:
    """A gold arrow pointing up: what the action gives."""
    c = Canvas(12, 12)
    for row in range(5):
        c.hline(5 - row, 6 + row, 1 + row, P["gold"])
    c.hline(1, 10, 5, P["gold_dark"])
    c.rect(4, 6, 4, 5, P["gold"])
    c.vline(4, 6, 10, P["gold_light"])
    c.outline()
    return c


def icon_time() -> Canvas:
    """An hourglass: turns to wait."""
    c = Canvas(12, 12)
    c.hline(2, 9, 0, P["wood_dark"])
    c.hline(2, 9, 11, P["wood_dark"])
    c.hline(2, 9, 1, P["wood"])
    c.hline(2, 9, 10, P["wood"])
    for row, (x0, x1) in enumerate(((3, 8), (3, 8), (4, 7), (5, 6), (5, 6), (4, 7), (3, 8), (3, 8))):
        c.hline(x0, x1, 2 + row, P["paper"])
    c.hline(4, 7, 3, P["thatch"])
    c.hline(5, 6, 4, P["thatch"])
    c.px(5, 6, P["thatch"])
    c.hline(4, 7, 8, P["thatch"])
    c.hline(3, 8, 9, P["thatch_dark"])
    c.outline()
    return c


def icon_scroll() -> Canvas:
    """Bí kíp đột phá: a rolled scroll tied with a red cord."""
    c = Canvas(12, 12)
    c.rect(2, 3, 8, 6, P["paper"])
    c.hline(2, 9, 8, P["paper_shade"])
    c.rect(1, 2, 2, 8, P["wood"])
    c.rect(9, 2, 2, 8, P["wood"])
    c.vline(1, 2, 9, P["wood_light"])
    c.vline(9, 2, 9, P["wood_light"])
    c.rect(5, 3, 2, 6, P["red"])
    c.px(5, 4, P["red_light"] if "red_light" in P else P["red"])
    c.outline()
    return c


REQUIREMENT_ICONS = (("check", icon_check), ("cross", icon_cross), ("gain", icon_gain), ("time", icon_time),
                     ("scroll", icon_scroll))


def app_icon() -> Canvas:
    """The game's icon (Android launcher, window): the level 6 castle on a sky and grass tile."""
    c = Canvas(48, 48)
    for y in range(48):
        c.hline(0, 47, y, P["roof_light"] if y < 30 else P["grass"])
    c.hline(0, 47, 30, P["grass_dark"] if "grass_dark" in P else P["grass"])
    c.paste(castle(6), 8, 10)
    for i in range(48):
        for x, y in ((i, 0), (i, 47), (0, i), (47, i)):
            c.px(x, y, P["outline"])
    return c


def main() -> None:
    app_icon().save("ui/app_icon.png", 4)
    tile_grass().save("tiles/grass.png")
    tile_farmland().save("tiles/farmland.png")
    tile_forest().save("tiles/forest.png")
    tile_hill().save("tiles/hill.png")
    tile_wild().save("tiles/wild.png")
    key_marker().save("tiles/key.png")
    key_frame().save("tiles/key_frame.png")
    for level in range(1, 7):
        castle(level).save(f"buildings/castle_{level}.png")
        level_badge(level).save(f"buildings/level_{level}.png")
    for turns in range(1, 8):
        turns_badge(turns).save(f"buildings/turns_{turns}.png")
    foundation().save("buildings/foundation.png")
    scaffold().save("buildings/scaffold.png")
    anim_strip(scaffold).save("buildings/scaffold_anim.png")
    for level in range(1, 7):
        anim_strip(lambda f, lv=level: castle(lv, f)).save(f"buildings/castle_{level}_anim.png")
    for name, draw in (("barracks", barracks), ("watchtower", watchtower), ("farm", farm),
                       ("lumber_mill", lumber_mill), ("mine", mine), ("war_stable", war_stable),
                       ("archery_range", archery_range), ("martial_hall", martial_hall),
                       ("military_academy", military_academy), ("market", market), ("granary", granary),
                       ("academy", academy), ("infirmary", infirmary), ("magistrate", magistrate), ("police", police)):
        anim_strip(draw).save(f"buildings/{name}_anim.png")
    barracks().save("buildings/barracks.png")
    watchtower().save("buildings/watchtower.png")
    farm().save("buildings/farm.png")
    lumber_mill().save("buildings/lumber_mill.png")
    mine().save("buildings/mine.png")
    for name, draw in (("war_stable", war_stable), ("archery_range", archery_range), ("martial_hall", martial_hall),
                       ("military_academy", military_academy), ("market", market), ("granary", granary),
                       ("academy", academy), ("infirmary", infirmary), ("magistrate", magistrate), ("police", police)):
        draw().save(f"buildings/{name}.png")
    for name, draw in (("food", icon_food), ("wood", icon_wood), ("stone", icon_stone), ("ore", icon_ore),
                       ("hardwood", icon_hardwood), ("horses", icon_horses)):
        draw().save(f"icons/{name}.png", UI_SCALE)
    for name, draw in REQUIREMENT_ICONS:
        draw().save(f"icons/{name}.png", UI_SCALE)
    panel_paper().save("ui/panel_paper.png", UI_SCALE)
    panel_wood().save("ui/panel_wood.png", UI_SCALE)
    panel_inset().save("ui/panel_inset.png", UI_SCALE)
    for state in ("normal", "hover", "pressed", "disabled"):
        button(state).save(f"ui/button_{state}.png", UI_SCALE)
    tab(True).save("ui/tab_selected.png", UI_SCALE)
    tab(False).save("ui/tab_unselected.png", UI_SCALE)
    battle_art.draw_all()
    item_art.draw_all()
    portrait_art.draw_all()
    world_art.draw_all()
    map_art.draw_all()
    print("Art written to", ASSETS)


if __name__ == "__main__":
    main()
