"""Portrait parts for generals and advisors (GDD §13, M12c): 48×48 layers stacked by the game
(PortraitView) and tinted from each officer's OfficerLook. Called by generate.py.

Tinted layers are drawn in grays (light = 245, base = 205, shade = 150, deep = 105) and the game
multiplies them by the right color: skin, hair, accent (plume, hat band, hairpin) or the side's
color (armor cloth, robe). Untinted layers (eyes, mouth, metal, frames) are in full color.
Part counts must match OfficerLook (HAIR_STYLES, EYE_STYLES, BROW_STYLES, BEARD_STYLES).
"""

import random

from pathlib import Path

from PIL import Image

import item_art
from pixel import ASSETS, CLEAR, P, Canvas, hex_color

S = 48
# Portraits are 96×96 (the size of hand-drawn / AI portraits in assets/portraits/pool/). Background
# and frames are drawn at that size; the 48×48 parts are doubled to fill it.
F = 96
PART_SCALE = 2
G_LIGHT, G_BASE, G_SHADE, G_DEEP = (hex_color("f5f5f5"), hex_color("cdcdcd"), hex_color("969696"),
                                    hex_color("696969"))
K = {
    "line": hex_color("3a2418"), "white": hex_color("fdfbf6"), "iris": hex_color("4a2c1c"),
    "iris_light": hex_color("8a5a3a"), "shine": hex_color("ffffff"), "lip": hex_color("c8505a"),
    "blush": hex_color("f2a2a0"), "mouth": hex_color("8a4636"),
    "gold": hex_color("f2c23c"), "gold_dark": hex_color("b9862a"), "gold_light": hex_color("fff0a0"),
    "iron": hex_color("8a94a4"), "iron_dark": hex_color("5a6270"), "iron_light": hex_color("c4ccd8"),
    "hat": hex_color("26201c"), "hat_light": hex_color("4a403a"),
}


def face_half_width(y: int, female: bool) -> float:
    """Half the face's width on row y (head from y=10 to the chin)."""
    if y < 10:
        return 0
    if y <= 20:
        return 8.6 * (1 - ((20 - y) / 10.5) ** 2) ** 0.5
    chin = 32 if female else 33
    if y <= 27:
        return 8.6 if not female else 8.2
    if y > chin:
        return 0
    taper = (y - 27) / (chin - 27)
    return (8.6 if not female else 8.2) * (1 - taper * (0.75 if female else 0.6))


def face(female: bool) -> Canvas:
    c = Canvas(S, S)
    for y in range(10, 34):
        half = face_half_width(y, female)
        if half <= 0:
            continue
        x0, x1 = round(24 - half), round(23 + half)
        c.hline(x0, x1, y, G_BASE)
        c.px(x0, y, G_SHADE)
        c.px(x1, y, G_SHADE)
    for y in range(20, 25):  # ears
        c.px(15, y, G_BASE)
        c.px(32, y, G_BASE)
    c.px(15, 22, G_SHADE)
    c.px(32, 22, G_SHADE)
    c.rect(20, 32, 8, 6, G_BASE)  # neck
    c.hline(20, 27, 32, G_SHADE)
    c.vline(20, 33, 37, G_SHADE)
    c.px(24, 26, G_SHADE)  # nose
    c.px(23, 27, G_SHADE)
    for x in range(18, 30):  # cheek light
        if 20 <= x <= 27:
            c.px(x, 13, G_LIGHT)
    c.outline(K["line"])
    return c


def eyes(style: int, female: bool) -> Canvas:
    """Large anime eyes, mirrored; women get heavier lashes."""
    c = Canvas(S, S)
    for left in (True, False):
        x0 = 17 if left else 27
        def px(dx, y, color):
            c.px(x0 + (dx if left else 4 - dx), y, color)
        if style == 0:  # big and round
            top, height = 21, 5
        elif style == 1:  # sharp
            top, height = 22, 3
        else:  # gentle, drooping at the outer corner
            top, height = 21, 4
        for dx in range(5):
            for y in range(top + 1, top + height):
                px(dx, y, K["white"])
        for dx in range(5):
            lash_y = top + (1 if style == 1 and dx < 2 else 0) + (1 if style == 2 and dx == 0 else 0)
            px(dx, lash_y, K["line"])
            if female:
                px(dx, lash_y - (1 if dx < 3 else 0), K["line"])
        if female:
            px(-1, top, K["line"])
        for y in range(top + 1, top + height):
            px(2, y, K["iris"])
            px(3, y, K["iris"])
        px(2, top + height - 1, K["iris_light"])
        px(3, top + 1, K["shine"])
        px(4, top + height, K["line"]) if style != 1 else None
    return c


def brows(style: int) -> Canvas:
    c = Canvas(S, S)
    for left in (True, False):
        for dx in range(5):
            x = 17 + dx if left else 31 - dx
            y = 18 if style == 0 else (19 - (dx // 2) if left else 19 - (dx // 2))
            if style == 1:
                y = 17 + dx // 2  # angled up toward the middle: a determined look
            c.px(x, y, G_SHADE)
            if dx in (1, 2):
                c.px(x, y - 1 if style == 0 else y, G_DEEP)
    return c


def mouth(female: bool) -> Canvas:
    c = Canvas(S, S)
    if female:
        c.hline(23, 24, 29, K["lip"])
        c.px(22, 29, K["mouth"])
        c.px(25, 29, K["mouth"])
        for x in (18, 19, 28, 29):
            c.px(x, 27, K["blush"])
    else:
        c.hline(22, 25, 29, K["mouth"])
        c.px(24, 30, K["lip"])
    return c


def hair_cap(c: Canvas, low: int = 15) -> None:
    """Hair over the top of the head down to row `low` at the sides."""
    for y in range(8, low + 1):
        half = face_half_width(max(y, 10), False) + 1.2 if y >= 10 else 6.5 - (10 - y) * 1.5
        if half <= 0:
            continue
        c.hline(round(24 - half), round(23 + half), y, G_BASE)
    for x in range(19, 29):
        c.px(x, 9, G_LIGHT)


def hair_front(style: int, female: bool) -> Canvas:
    c = Canvas(S, S)
    hair_cap(c, 14)
    if not female:
        if style == 0:  # topknot with sideburns
            c.ellipse(24, 6, 3.2, 2.6, G_BASE)
            c.hline(22, 26, 8, G_DEEP)
            for y in range(15, 23):
                c.px(15, y, G_BASE)
                c.px(32, y, G_BASE)
        elif style == 1:  # loose bangs
            for x in range(16, 32, 3):
                c.vline(x, 14, 17, G_BASE)
                c.vline(x + 1, 14, 16, G_SHADE)
        else:  # spiky
            for i, x in enumerate(range(15, 33, 3)):
                for d in range(4):
                    c.px(x + d // 2, 8 - d + (i % 2), G_BASE)
            for x in range(17, 31, 4):
                c.vline(x, 14, 16, G_BASE)
    else:
        if style == 0:  # straight bangs and long side locks
            c.rect(16, 14, 16, 3, G_BASE)
            for x in range(17, 31, 3):
                c.px(x, 17, G_SHADE)
            c.rect(14, 15, 3, 18, G_BASE)
            c.rect(31, 15, 3, 18, G_BASE)
        elif style == 1:  # side-swept bangs, double bun on top
            for y in range(14, 18):
                c.hline(16, 31 - (y - 14) * 3, y, G_BASE)
            c.ellipse(18, 6, 3.4, 3, G_BASE)
            c.ellipse(30, 6, 3.4, 3, G_BASE)
            c.px(18, 5, G_LIGHT)
            c.px(30, 5, G_LIGHT)
        else:  # bangs with twin tails tied at the sides
            for x in range(16, 32, 2):
                c.vline(x, 14, 16 + (x % 4 == 0), G_BASE)
            c.rect(12, 14, 3, 4, G_BASE)
            c.rect(33, 14, 3, 4, G_BASE)
    # Shading along the bottom edge of the cap.
    for y in range(c.height):
        for x in range(c.width):
            if c.get(x, y) == G_BASE and (y + 1 >= c.height or c.get(x, y + 1)[3] == 0):
                c.px(x, y, G_SHADE)
    c.outline(K["line"])
    return c


def hair_back(style: int, female: bool) -> Canvas:
    c = Canvas(S, S)
    if female and style == 0:  # long hair behind the shoulders
        for y in range(12, 42):
            half = 10.5 if y < 36 else 10.5 - (y - 36) * 1.2
            c.hline(round(24 - half), round(23 + half), y, G_SHADE)
    elif female and style == 2:  # twin tails
        for x0 in (9, 35):
            for y in range(17, 42):
                w = 4 if y < 36 else 3
                c.hline(x0, x0 + w - 1, y, G_SHADE)
                if y % 5 == 0:
                    c.hline(x0, x0 + w - 1, y, G_DEEP)
    elif not female and style == 1:  # long hair tied low
        for y in range(14, 36):
            half = 9.5
            c.hline(round(24 - half), round(23 + half), y, G_SHADE)
    c.outline(K["line"])
    return c


def beard(style: int) -> Canvas:
    c = Canvas(S, S)
    if style == 1:  # mustache
        c.hline(20, 22, 28, G_BASE)
        c.hline(25, 27, 28, G_BASE)
        c.px(19, 29, G_BASE)
        c.px(28, 29, G_BASE)
    elif style == 2:  # long beard (Quan Vũ style)
        c.hline(20, 27, 28, G_BASE)
        for y in range(30, 41):
            half = 4 - max(0, y - 36) * 0.7
            c.hline(round(24 - half), round(23 + half), y, G_BASE)
        c.vline(23, 31, 39, G_SHADE)
        c.hline(22, 25, 29, CLEAR)
    if style:
        c.outline(K["line"])
    return c


def body(kind: str) -> tuple:
    """Shoulders and chest: armor for generals, a scholar's robe for advisors. Returns the full
    color layer and the side-colored layer."""
    base = Canvas(S, S)
    team = Canvas(S, S)
    if kind == "general":
        for y in range(37, 48):
            half = 14 + min(4, (y - 37) // 2)
            team.hline(24 - half, 23 + half, y, G_BASE)
        for y in range(39, 48, 2):
            for x in range(17 + (y // 2) % 2, 31, 2):
                team.px(x, y, G_SHADE)
        for x0 in (6, 30):  # shoulder plates
            for row in range(5):
                base.hline(x0 + (2 - row if x0 == 6 else 0), x0 + 11 - (0 if x0 == 6 else 2 - row) if row < 3 else x0 + 11, 36 + row, K["iron"])
            base.hline(x0, x0 + 11, 40, K["gold"])
            base.hline(x0 + 2, x0 + 9, 36, K["iron_light"])
        base.hline(19, 28, 37, K["gold"])
        base.rect(22, 41, 4, 3, K["gold"])
        base.px(23, 42, K["gold_light"])
    else:
        for y in range(36, 48):
            half = 13 + min(6, (y - 36) // 2)
            team.hline(24 - half, 23 + half, y, G_BASE)
        for y in range(36, 48):  # crossed white collar
            d = y - 36
            base.px(20 + d // 2, y, K["white"]) if d < 12 else None
            base.px(27 - d // 2, y, K["white"]) if d < 12 else None
            base.px(21 + d // 2, y, K["white"]) if d < 10 else None
        for y in range(40, 48):
            team.px(10, y, G_SHADE)
            team.px(37, y, G_SHADE)
    team.outline(K["line"])
    return base, team


def helmet() -> tuple:
    """The general's gold helmet with cheek guards; the accent layer holds two long feathers."""
    c = Canvas(S, S)
    accent = Canvas(S, S)
    for y in range(6, 16):
        half = 10 - max(0, 9 - y) * 1.1
        c.hline(round(24 - half), round(23 + half), y, K["gold"])
    c.hline(13, 34, 15, K["gold_dark"])
    c.hline(12, 35, 16, K["gold_dark"])
    for y in range(16, 24):  # cheek guards
        c.hline(13, 15, y, K["gold"])
        c.hline(32, 34, y, K["gold"])
    c.rect(22, 8, 4, 4, K["iron"])  # front crest
    c.px(23, 9, K["iron_light"])
    for x in range(17, 31):
        c.px(x, 7, K["gold_light"])
    # Two long pheasant feathers rising from the crest and curling outward at the tips.
    path = [(22, 7), (21, 6), (20, 5), (18, 4), (16, 4), (14, 4), (12, 5), (10, 6), (9, 7)]
    for i, (x, y) in enumerate(path):
        for mirror in (False, True):
            fx = 47 - x if mirror else x
            accent.px(fx, y, G_BASE)
            accent.px(fx, y + 1, G_SHADE if i % 2 else G_BASE)
            if i % 2 == 0:
                accent.px(fx, y + 2, G_DEEP)
    c.outline(K["line"])
    accent.outline(K["line"])
    return c, accent


def scholar_hat() -> tuple:
    """Mũ cánh chuồn: the official's rounded black cap with two flat wings, and a band (accent)."""
    c = Canvas(S, S)
    accent = Canvas(S, S)
    for y in range(4, 13):
        half = 7 - max(0, 6 - y) * 0.8
        c.hline(round(24 - half), round(23 + half), y, K["hat"])
    c.hline(19, 28, 5, K["hat_light"])
    for x0, x1 in ((6, 16), (31, 41)):  # the wings
        c.hline(x0, x1, 8, K["hat"])
        c.hline(x0 + 1, x1 - 1, 9, K["hat"])
        c.hline(x0 + 1, x1 - 1, 7, K["hat_light"])
    accent.hline(17, 30, 11, G_BASE)
    accent.hline(18, 29, 12, G_SHADE)
    c.outline(K["line"])
    accent.outline(K["line"])
    return c, accent


def hairpin() -> tuple:
    c = Canvas(S, S)
    accent = Canvas(S, S)
    c.hline(29, 37, 9, K["gold"])
    accent.ellipse(37.5, 8.5, 2.4, 2.4, G_BASE)
    accent.px(37, 8, G_LIGHT)
    for y in (11, 13, 15):  # dangling beads
        c.px(36, y, K["gold"])
    c.vline(36, 10, 15, K["gold_dark"])
    c.outline(K["line"])
    accent.outline(K["line"])
    return c, accent


def background() -> Canvas:
    rng = random.Random(4)
    c = Canvas(F, F)
    top, bottom = hex_color("bcd8ee"), hex_color("f1e6c6")
    for y in range(F):
        mix = y / (F - 1)
        color = tuple(round(top[i] * (1 - mix) + bottom[i] * mix) for i in range(3)) + (255,)
        c.hline(0, F - 1, y, color)
    far = hex_color("a9c0d4")
    for x in range(F):
        peak = 63 + int(8 * abs(((x * 2) % 36) / 18 - 1))
        for y in range(peak, F):
            c.px(x, y, far)
    for _ in range(9):
        c.px(rng.randrange(F), rng.randrange(6, 42), hex_color("e8f2fa"))
    return c


# Frames by star tier (PortraitView.frame_part): 1–2★ bronze, 3★ green, 4★ blue with small
# studs, 5★ purple with ornaments, 6★ gold with rich ornaments (the item frames' style, M12e).
FRAME_TIERS = [(("bronze", "bronze_light", "bronze_dark"), 0), (("jade_dark", "jade", "jade_dark"), 0),
               (("cloth", "cloth_light", "cloth_dark"), 1), (("purple", "purple_light", "purple_dark"), 2),
               (("gold", "gold_light", "gold_dark"), 3)]


def frame(tier: int) -> Canvas:
    """The border covers the outer 4 px of the portrait; corner ornaments reach a little further."""
    colors, pattern = FRAME_TIERS[tier]
    return item_art.frame(F, colors, pattern, None, 3)


# Ruler frames unlocked by achievements (M18b, GDD §30): ngọc bích, son đỏ, bạch ngân.
RULER_FRAMES = {"jade": ("jade", "jade_light", "jade_dark"), "crimson": ("lacquer", "red_light", "bronze_dark"),
                "silver": ("steel", "edge", "steel_dark")}


def ruler_frame(frame_id: str) -> Canvas:
    """A rich frame (pattern 3) in the reward's colors."""
    return item_art.frame(F, RULER_FRAMES[frame_id], 3, None, 3)


def black_market_merchant() -> Canvas:
    """The black market's merchant (M16d): a wide straw hat shading the eyes, a black hooded
    cloak, a sly grin with a gold tooth and a coin, in a night alley lit by a lantern. 96×96,
    background included (GameArt.npc_portrait)."""
    night_top, night_bottom = hex_color("2a2238"), hex_color("4a3a4e")
    bg = Canvas(F, F)
    for y in range(F):
        mix = y / (F - 1)
        color = tuple(round(night_top[i] * (1 - mix) + night_bottom[i] * mix) for i in range(3)) + (255,)
        bg.hline(0, F - 1, y, color)
    glow = hex_color("7a4a3a")
    bg.ellipse(18, 22, 16, 16, glow)
    bg.ellipse(18, 22, 9, 9, hex_color("b8703e"))
    bg.rect(14, 16, 9, 12, hex_color("e0913e"))  # lantern
    bg.hline(14, 22, 16, hex_color("8e2a1e"))
    bg.hline(14, 22, 27, hex_color("8e2a1e"))
    bg.vline(18, 8, 15, hex_color("1a1420"))
    c = Canvas(S, S)
    cloak, cloak_light, cloak_dark = hex_color("221d29"), hex_color("3a3346"), hex_color("141018")
    for y in range(30, S):  # shoulders and cloak
        half = min(22, 9 + (y - 30) * 1.4)
        c.hline(round(24 - half), round(23 + half), y, cloak)
    for y in range(12, 36):  # hood around the face
        half = 9 + (y - 12) * 0.25
        c.hline(round(24 - half), round(23 + half), y, cloak)
    for y in range(31, S):
        c.px(round(24 - min(22, 9 + (y - 30) * 1.4)) + 1, y, cloak_light)
        c.px(24, y, cloak_dark)
    skin, skin_shade, skin_dark = hex_color("e2b48c"), hex_color("b98a66"), hex_color("7a5640")
    for y in range(21, 33):  # face, narrowing to the chin
        half = 6 if y < 29 else 6 - (y - 28) * 1.2
        c.hline(round(24 - half), round(23 + half), y, skin)
    for y in range(21, 25):  # the hat's shadow over the eyes
        half = 6
        c.hline(round(24 - half), round(23 + half), y, skin_dark if y < 23 else skin_shade)
    c.px(20, 23, hex_color("f2d24a"))  # eyes glinting in the shade
    c.px(27, 23, hex_color("f2d24a"))
    c.px(24, 25, skin_shade)  # nose
    c.px(24, 26, skin_shade)
    line, teeth = hex_color("3a2418"), hex_color("fdfbf6")
    c.hline(20, 27, 29, line)  # grin
    c.px(19, 28, line)
    c.px(28, 28, line)
    c.hline(20, 27, 28, teeth)
    c.px(25, 28, hex_color("f2c23c"))  # gold tooth
    c.px(18, 27, line)
    c.px(29, 27, line)
    straw, straw_light, straw_dark = hex_color("8a6a3a"), hex_color("b08a50"), hex_color("5e4626")
    for y in range(6, 20):  # conical hat
        half = (y - 5) * 1.1
        c.hline(round(24 - half), round(23 + half), y, straw)
        c.px(round(24 - half), y, straw_light)
    c.hline(5, 42, 20, straw)  # brim
    c.hline(4, 43, 21, straw_dark)
    c.hline(8, 39, 19, straw_light)
    for x in range(10, 38, 4):
        c.px(x, 20, straw_dark)
    hand = hex_color("d8a880")
    c.rect(33, 38, 4, 3, hand)  # hand with a coin
    c.ellipse(36.5, 37, 2.6, 2.6, hex_color("f2c23c"))
    c.px(36, 36, hex_color("fff0a0"))
    c.outline(line)
    full = Canvas(F, F)
    full.paste(bg, 0, 0)
    full.image.alpha_composite(c.image.resize((F, F), Image.NEAREST))
    return full


# --- The ruler (Chúa công, M16h) --------------------------------------------------------------
RULER_OUTFITS = ("dragon", "armor", "brocade")
RK = {
    "yellow": hex_color("f0c030"), "yellow_dark": hex_color("c08a1a"), "yellow_light": hex_color("fff09a"),
    "red": hex_color("b8281e"), "red_dark": hex_color("7e1a14"), "jade": hex_color("3aa07a"),
}


def ruler_body(outfit: str) -> tuple:
    """The ruler's shoulders: a yellow dragon robe with a red collar and a gold dragon coil; gold
    armor over the side's color with a red cape; a brocade robe in the side's color with gold
    dots. Returns the full color layer and the side-colored layer."""
    if outfit == "armor":
        base, team = body("general")
        for y in range(36, 48):  # red cape at the shoulders' edges
            base.hline(4, 6, y, RK["red"])
            base.hline(41, 43, y, RK["red"])
        base.rect(20, 42, 8, 3, K["gold"])
        base.hline(21, 26, 43, K["gold_light"])
        base.outline(K["line"])
        return base, team
    base = Canvas(S, S)
    team = Canvas(S, S)
    fill, shade = (RK["yellow"], RK["yellow_dark"]) if outfit == "dragon" else (None, None)
    target = team if outfit == "brocade" else base
    for y in range(36, 48):
        half = 13 + min(6, (y - 36) // 2)
        target.hline(24 - half, 23 + half, y, fill or G_BASE)
        target.px(24 - half, y, shade or G_SHADE)
        target.px(23 + half, y, shade or G_SHADE)
    collar = RK["red"] if outfit == "dragon" else K["white"]
    for y in range(36, 48):
        d = y - 36
        if d < 12:
            base.px(20 + d // 2, y, collar)
            base.px(27 - d // 2, y, collar)
        if d < 10:
            base.px(21 + d // 2, y, collar)
    if outfit == "dragon":  # gold dragon coils on both shoulders
        for cx in (12, 35):
            for i, (dx, dy) in enumerate(((0, 0), (1, -1), (2, 0), (2, 1), (1, 2), (0, 2), (-1, 1))):
                base.px(cx + dx, 41 + dy, RK["yellow_light"] if i % 2 else K["gold_dark"])
            base.px(cx + 1, 41, RK["red"])
    else:  # brocade
        for y in range(39, 48, 3):
            for x in range(9 + (y % 2) * 2, 40, 4):
                if not 18 <= x <= 29:
                    base.px(x, y, K["gold"])
    base.outline(K["line"])
    team.outline(K["line"])
    return base, team


def ruler_hat(outfit: str, female: bool) -> tuple:
    """The ruler's headgear (and its accent layer): an imperial mũ miện with bead strings, or a
    gold phoenix crown for a woman; a gold helmet with a red tassel and a plume; a black official's
    cap or a gold-pinned bun."""
    c = Canvas(S, S)
    accent = Canvas(S, S)
    if outfit == "dragon" and not female:
        for y in range(5, 12):  # the cap
            c.hline(17, 30, y, K["hat"])
        c.hline(18, 29, 6, K["hat_light"])
        c.hline(10, 37, 3, K["hat"])  # the flat board
        c.hline(10, 37, 4, K["gold"])
        c.hline(11, 36, 2, K["gold_dark"])
        for x in range(11, 37, 3):  # bead strings in front of the brow
            for y in range(5, 9 + (x // 3) % 2):
                c.px(x, y, K["gold_light"] if y % 2 else RK["red"])
        accent.hline(17, 30, 11, G_BASE)
    elif outfit == "dragon":
        for y in range(4, 13):
            half = 9 - max(0, 7 - y)
            c.hline(24 - half, 23 + half, y, K["gold"])
        c.hline(16, 31, 12, K["gold_dark"])
        c.ellipse(24, 8, 2.5, 2.5, RK["red"])
        c.px(23, 7, K["gold_light"])
        for x0 in (8, 37):  # phoenix wings and dangling beads
            c.hline(x0, x0 + 3, 7, K["gold"])
            c.vline(x0 + 1, 8, 15, K["gold_dark"])
        for x in (9, 38):
            accent.px(x, 16, G_BASE)
            accent.px(x, 17, G_SHADE)
        accent.ellipse(24, 3, 2, 1.6, G_BASE)
    elif outfit == "armor":
        base, feathers = helmet()
        c.paste(base, 0, 0)
        c.rect(22, 3, 4, 3, RK["red"])  # red tassel on the crest
        accent.paste(feathers, 0, 0)
    elif outfit == "brocade" and not female:
        base, band = scholar_hat()
        c.paste(base, 0, 0)
        c.rect(22, 6, 4, 2, K["gold"])
        accent.paste(band, 0, 0)
    else:  # brocade, a woman
        base, ornament = hairpin()
        c.paste(base, 0, 0)
        c.hline(18, 28, 6, K["gold"])
        accent.paste(ornament, 0, 0)
    if outfit == "dragon":
        c.outline(K["line"])
        accent.outline(K["line"])
    return c, accent


def save_part(part: Canvas, relative: str) -> None:
    """Saves a 48×48 part doubled onto the 96×96 portrait canvas."""
    full = Canvas(F, F)
    full.image.alpha_composite(part.image.resize((S * PART_SCALE, S * PART_SCALE), Image.NEAREST))
    full.save(relative)


def draw_all() -> None:
    background().save("portraits/bg.png")
    for tier in range(len(FRAME_TIERS)):
        frame(tier).save(f"portraits/frame_{tier}.png")
    for frame_id in RULER_FRAMES:
        ruler_frame(frame_id).save(f"portraits/frame_ruler_{frame_id}.png")
    (Path(ASSETS) / "portraits" / "pool").mkdir(parents=True, exist_ok=True)
    for gender, female in (("m", False), ("f", True)):
        save_part(face(female), f"portraits/face_{gender}.png")
        save_part(mouth(female), f"portraits/mouth_{gender}.png")
        for style in range(3):
            save_part(eyes(style, female), f"portraits/eyes_{style}_{gender}.png")
            save_part(hair_front(style, female), f"portraits/hair_front_{gender}_{style}.png")
            save_part(hair_back(style, female), f"portraits/hair_back_{gender}_{style}.png")
    black_market_merchant().save("portraits/npc/black_market.png")
    for style in range(2):
        save_part(brows(style), f"portraits/brows_{style}.png")
    for style in (1, 2):
        save_part(beard(style), f"portraits/beard_{style}.png")
    for kind in ("general", "advisor"):
        base, team = body(kind)
        save_part(base, f"portraits/body_{kind}.png")
        save_part(team, f"portraits/body_{kind}_team.png")
    for outfit in RULER_OUTFITS:
        base, team = ruler_body(outfit)
        save_part(base, f"portraits/body_ruler_{outfit}.png")
        save_part(team, f"portraits/body_ruler_{outfit}_team.png")
        for gender, female in (("m", False), ("f", True)):
            base, accent = ruler_hat(outfit, female)
            save_part(base, f"portraits/ruler_hat_{outfit}_{gender}.png")
            save_part(accent, f"portraits/ruler_hat_{outfit}_{gender}_accent.png")
    for name, draw in (("helmet", helmet), ("scholar_hat", scholar_hat), ("hairpin", hairpin)):
        base, accent = draw()
        save_part(base, f"portraits/{name}.png")
        save_part(accent, f"portraits/{name}_accent.png")
