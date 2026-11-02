"""Officers on foot (M16h, GDD §24): generals without their horse and the player's ruler (Chúa
công), 32×36 with OFFICER_FRAMES frames per state, for the duel mini game (M16j) and the ruler on
the town walls. Called by generate.py.

Layers like the mounted officers (battle_art.split_layers): clothes in the side's color, hair and
accent in the officer's colors. Generals come in the mounted tiers (1–2★ leather, 3–4★ lamellar,
5–6★ gold) with their worn weapon; the ruler has one of RULER_OUTFITS and carries a sword only in
armor.
"""

from battle_art import (ACCENT, ACCENT_DARK, C, GENERAL_WEAPONS, HAIR, HAIR_DARK, OFFICER_FRAMES, OFFICER_TIERS,
                        TEAM, TEAM_DARK, TEAM_LIGHT, WALK_LIFT, general_weapon, guandao_turned, save_sheet, sheet,
                        split_layers)
from pixel import Canvas, hex_color

W, H = 32, 36
# Ruler outfits (Ruler.OUTFIT_NAMES): imperial dragon robe, war armor, brocade.
RULER_OUTFITS = ("dragon", "armor", "brocade")
R = {
    "yellow": hex_color("f0c030"), "yellow_dark": hex_color("c08a1a"), "yellow_light": hex_color("fff09a"),
    "red": hex_color("b8281e"), "jade": hex_color("3aa07a"),
}
# Leg x offsets (back, front) per walk frame, and the body's bob.
STRIDE = ((0, 0), (-2, 2), (0, 0), (2, -2))


def _legs(c: Canvas, state: str, frame: int, lift: int, robe: bool) -> None:
    back, front = STRIDE[frame] if state == "walk" else (0, 0)
    if state == "attack":
        back, front = ((0, 0), (-1, 1), (-1, 2), (0, 1))[frame]
    if robe:  # only the shoes show under a long robe
        c.hline(11 + back, 13 + back, 34, C["boot"])
        c.hline(15 + front, 17 + front, 34, C["boot"])
        c.hline(11 + back, 13 + back, 35, C["boot"])
        c.hline(15 + front, 17 + front, 35, C["boot"])
        return
    for x, color in ((12 + back, C["pants"]), (15 + front, C["pants"])):
        c.rect(x, 27 - lift, 2, 7 + lift, color)
        c.hline(x, x + 2, 34, C["boot"])
        c.hline(x, x + 2, 35, C["boot"])


def _head(c: Canvas, hy: int, female: bool, frame: int) -> None:
    """The face (4×5) with its top-left corner at (12, hy); long hair down the back for women."""
    c.rect(12, hy, 4, 5, C["skin"])
    c.vline(12, hy, hy + 4, C["skin_dark"])
    c.px(15, hy + 2, C["eye"])
    if female:
        sway = (0, 1, 1, 0)[frame]
        for y in range(hy, hy + 9):
            c.hline(10 - (y - hy) // 4 - sway * (y > hy + 4), 11, y, HAIR if y < hy + 5 else HAIR_DARK)


def _general_helmet(c: Canvas, hy: int, tier: int, frame: int) -> None:
    sway = (0, 0, 1, 1)[frame]
    if tier == 1:  # an iron cap with a short plume
        c.hline(12, 15, hy - 1, C["iron"])
        c.px(13, hy - 1, C["iron_light"])
        c.px(11, hy, C["iron_dark"])
        c.px(13, hy - 2, ACCENT)
        c.px(12 - sway, hy - 3, ACCENT_DARK)
    elif tier == 2:  # an iron helmet with a red tassel and a plume
        c.hline(11, 16, hy - 1, C["iron"])
        c.hline(12, 15, hy - 2, C["iron"])
        c.px(13, hy - 2, C["iron_light"])
        c.px(11, hy, C["iron_dark"])
        c.px(14, hy - 3, C["tassel"])
        for i, (x, y) in enumerate(((12, hy - 3), (11, hy - 4), (10, hy - 4 + sway))):
            c.px(x, y, ACCENT if i % 2 == 0 else ACCENT_DARK)
    else:  # a gold helmet with two long pheasant feathers
        c.hline(11, 16, hy - 1, C["gold"])
        c.hline(12, 15, hy - 2, C["gold"])
        c.px(13, hy - 2, C["gold_light"])
        c.px(11, hy, C["gold_dark"])
        feathers = ((12, hy - 3), (11, hy - 4), (10, hy - 4), (9, hy - 5), (8, hy - 5 + sway), (7, hy - 5 + sway))
        for i, (x, y) in enumerate(feathers):
            c.px(x, y, ACCENT if i % 2 == 0 else ACCENT_DARK)
            c.px(x + 1, y + 1, ACCENT_DARK)


def _armor(c: Canvas, top: int, tier: int) -> None:
    """Tunic in the side's color from `top`, with the tier's armor over it."""
    c.rect(11, top, 7, 9, TEAM)
    c.vline(11, top, top + 8, TEAM_DARK)
    c.vline(16, top + 1, top + 5, TEAM_LIGHT)
    c.rect(10, top + 8, 9, 4, TEAM_DARK)  # skirt
    if tier == 1:  # leather: a strap across the chest and a belt
        for i in range(6):
            c.px(16 - i, top + i, C["quiver"])
        c.hline(11, 17, top + 7, C["belt"])
    elif tier == 2:  # iron lamellar rows, pauldrons and tassets
        for y in (top + 1, top + 3, top + 5):
            c.hline(12, 17, y, C["iron"])
        c.px(14, top + 2, C["iron_light"])
        c.hline(11, 17, top + 7, C["belt"])
        c.hline(10, 12, top, C["iron"])
        c.hline(16, 18, top, C["iron"])
        for x in range(10, 19, 2):
            c.vline(x, top + 9, top + 11, C["iron"])
    else:  # gilded armor
        c.hline(11, 17, top + 7, C["gold"])
        c.hline(10, 12, top, C["gold"])
        c.hline(16, 18, top, C["gold"])
        c.px(17, top + 1, C["gold_dark"])
        c.rect(13, top + 2, 3, 3, C["gold"])
        c.px(14, top + 3, C["gold_light"])
        for x in range(10, 19, 2):
            c.vline(x, top + 9, top + 11, C["gold"])


def _cape(c: Canvas, top: int, frame: int, rows: int, color=TEAM_DARK) -> None:
    sway = (0, 1, 2, 1)[frame]
    for i in range(rows):
        x = 9 - i // 4 - (sway * i) // 8
        c.hline(x, 10, top + 1 + i, color)


def _robe(c: Canvas, top: int, fill, dark, light) -> None:
    """A long robe from the shoulders (`top`) to the feet, widening, with wide sleeves."""
    for y in range(top, 34):
        half = 3 + (y - top) // 4
        c.hline(14 - half, 14 + half, y, fill)
        c.px(14 - half, y, dark)
    c.rect(16, top + 1, 3, 6, light)  # sleeve
    c.vline(16, top + 1, top + 6, fill)


def _weapon(c: Canvas, state: str, frame: int, top: int, weapon_type: str) -> None:
    """The worn weapon: wind-up behind, raised overhead, swung forward, follow-through low
    (like the mounted commander's), held upright otherwise."""
    weapon, grip = general_weapon(weapon_type, frame % 2)
    if state == "attack" and frame == 0:
        c.paste(weapon, 8, max(0, top + 2 - grip))
        c.px(10, top + 2, C["skin"])
    elif state == "attack" and frame == 1:
        c.paste(weapon, 13, max(0, top - 2 - grip))
        c.px(14, top - 2, C["skin"])
    elif state == "attack":
        drop = 0 if frame == 2 else 3
        turned = guandao_turned(weapon)
        c.paste(turned, max(0, min(19 - (weapon.height - 1 - grip), W - 1 - weapon.height)), top + 3 + drop)
        c.px(19, top + 4 + drop, C["skin"])
    else:
        bounce = (0, 1, 1, 0)[frame] if state == "cheer" else 0
        hand_y = top + 5 - (3 + bounce if state == "cheer" else 0)
        c.paste(weapon, 18, max(0, hand_y - grip))
        c.px(19, hand_y, C["skin"])


def _pose(state: str, frame: int) -> tuple:
    """(lift, fallen): the body's bob and whether to lay the figure down."""
    lift = WALK_LIFT[frame] if state in ("walk", "cheer") else 0
    return lift, state == "fall"


def _fall(c: Canvas) -> Canvas:
    """The figure tipped over backwards for the fall state, lying on the ground in the frame."""
    fallen = Canvas(W, H)
    turned = c.image.rotate(90, expand=True)
    box = turned.getbbox()
    if box is None:
        return fallen
    turned = turned.crop(box)
    if turned.width > W:
        turned = turned.crop((turned.width - W, 0, turned.width, turned.height))
    fallen.image.alpha_composite(turned, ((W - turned.width) // 2, H - turned.height))
    return fallen


def general_foot_frame(state: str, frame: int, female: bool = False, weapon_type: str = "", tier: int = 3) -> tuple:
    """A general on foot: the mounted commander's armor, helmet and weapon by tier."""
    c = Canvas(W, H)
    lift, fallen = _pose(state, frame)
    top = 16 - lift
    if tier >= 2:
        _cape(c, top, frame, 14 if tier == 3 else 10)
    _legs(c, state, frame, lift, False)
    _armor(c, top, tier)
    c.vline(10, top + 1, top + 5, TEAM_DARK)  # back arm
    hy = top - 6
    _head(c, hy, female, frame)
    _general_helmet(c, hy, tier, frame)
    _weapon(c, state, frame, top, weapon_type)
    return split_layers(_fall(c) if fallen else c)


def ruler_frame(state: str, frame: int, female: bool = False, outfit: str = "dragon") -> tuple:
    """The player's ruler on foot in one of RULER_OUTFITS: a yellow dragon robe and an imperial
    crown (a flat-topped mũ miện with bead strings, or a woman's gold phoenix crown); gold armor,
    a red cape and a sword; a robe in the side's color with gold dots and a black cap or a bun.
    Raises a hand while cheering."""
    c = Canvas(W, H)
    lift, fallen = _pose(state, frame)
    top = 16 - lift
    hy = top - 6
    if outfit == "armor":
        _cape(c, top, frame, 15, C["lacquer"])
        _legs(c, state, frame, lift, False)
        _armor(c, top, 3)
        c.vline(10, top + 1, top + 5, TEAM_DARK)
        _head(c, hy, female, frame)
        c.hline(11, 16, hy - 1, C["gold"])  # gold helmet with a red tassel and a plume (accent)
        c.hline(12, 15, hy - 2, C["gold"])
        c.px(13, hy - 2, C["gold_light"])
        c.px(11, hy, C["gold_dark"])
        c.vline(13, hy - 4, hy - 3, C["tassel"])
        c.px(12, hy - 4, ACCENT)
        c.px(11, hy - 5 + (frame % 2), ACCENT_DARK)
        _weapon(c, state, frame, top, "kiem")
        return split_layers(_fall(c) if fallen else c)
    fill, dark, light = {
        "dragon": (R["yellow"], R["yellow_dark"], R["yellow_light"]),
        "brocade": (TEAM, TEAM_DARK, TEAM_LIGHT),
    }[outfit]
    sway = STRIDE[frame][1] if state == "walk" else 0
    _legs(c, state, frame, lift, True)
    _robe(c, top, fill, dark, light)
    if sway:
        c.hline(14 - 7 + sway, 14 + 7 + sway, 33, fill)
    if outfit == "dragon":  # red collar and hem, a coiled gold dragon on the chest
        c.vline(14, top, top + 4, R["red"])
        c.hline(9, 19, 33, R["red"])
        for x, y in ((12, top + 3), (13, top + 2), (14, top + 3), (15, top + 4), (14, top + 5), (13, top + 6)):
            c.px(x, y, R["yellow_light"])
        c.px(15, top + 2, R["red"])
        c.hline(11, 17, top + 7, R["red"])  # jade belt
        c.px(14, top + 7, R["jade"])
    else:  # brocade: white collar, gold dots, a gold belt
        c.vline(14, top, top + 3, C["feather"])
        for y in range(top + 9, 33, 3):
            for x in range(10 + (y % 2), 19, 3):
                c.px(x, y, C["gold"])
        c.hline(11, 17, top + 7, C["gold"])
    _head(c, hy, female, frame)
    if outfit == "dragon" and not female:  # mũ miện: a flat board with bead strings front and back
        c.rect(12, hy - 2, 4, 2, C["hat_black"])
        c.hline(10, 18, hy - 3, C["hat_black"])
        c.hline(10, 18, hy - 4, C["gold"])
        for x, length in ((17, 2), (18, 3), (10, 1)):
            c.vline(x, hy - 2, hy - 2 + length - (frame % 2 if x == 18 else 0), C["gold_light"])
    elif outfit == "dragon":  # phượng quan: a gold crown with a red gem and side ornaments
        c.rect(11, hy - 3, 6, 3, C["gold"])
        c.hline(12, 15, hy - 4, C["gold_light"])
        c.px(13, hy - 2, R["red"])
        c.px(17, hy - 2, ACCENT)
        c.vline(17, hy - 1, hy + 2, C["gold"])
        c.px(10, hy - 2, ACCENT)
    elif outfit == "brocade" and not female:  # black official's cap with short wings
        c.rect(11, hy - 3, 6, 3, C["hat_black"])
        c.hline(8, 10, hy - 2, C["hat_black"])
        c.hline(17, 19, hy - 2, C["hat_black"])
        c.hline(12, 15, hy - 1, ACCENT)
    else:  # brocade, a woman: a high bun with a hairpin
        c.rect(11, hy - 3, 5, 3, HAIR)
        c.ellipse(13.5, hy - 4, 2.2, 1.8, HAIR)
        c.hline(15, 18, hy - 4, ACCENT)
        c.px(18, hy - 5, C["gold"])
    # Hands: folded in the sleeve, raised while cheering, pointing forward while attacking.
    if state == "cheer":
        c.vline(19, top - 3 - (frame % 2), top + 1, light)
        c.px(19, top - 4 - (frame % 2), C["skin"])
    elif state == "attack":
        c.hline(19, 21 + (frame in (1, 2)), top + 3, light)
        c.px(22 + (frame in (1, 2)), top + 3, C["skin"])
    else:
        c.px(18, top + 6, C["skin"])
    return split_layers(_fall(c) if fallen else c)


def draw_all() -> None:
    """general_foot_<m|f>[_<weapon>]_t<tier> and ruler_<m|f>_<outfit> (GameArt.foot_sprite,
    GameArt.ruler_sprite)."""
    for gender, female in (("m", False), ("f", True)):
        for tier in OFFICER_TIERS:
            for weapon_type in GENERAL_WEAPONS:
                name = f"general_foot_{gender}" + (f"_{weapon_type}" if weapon_type else "") + f"_t{tier}"
                save_sheet(name, sheet(lambda s, f, fe=female, w=weapon_type, ti=tier:
                                       general_foot_frame(s, f, fe, w, ti), W, H, OFFICER_FRAMES))
        for outfit in RULER_OUTFITS:
            save_sheet(f"ruler_{gender}_{outfit}", sheet(lambda s, f, fe=female, o=outfit: ruler_frame(s, f, fe, o),
                                                          W, H, OFFICER_FRAMES))
