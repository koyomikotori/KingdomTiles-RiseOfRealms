"""Fighters on foot (M16h, GDD §24): generals without their horse and the sparring rivals (M16j),
32×36 with OFFICER_FRAMES frames per state, for the spar mini game. Called by generate.py.

Layers like the mounted officers (battle_art.split_layers): clothes in the side's color, hair and
accent in the officer's colors. Generals come in the mounted tiers (1–2★ leather, 3–4★ lamellar,
5–6★ gold) with their worn weapon; the rivals (NPC_FIGHTERS) wear their own fixed colors.
"""

from battle_art import (ACCENT, ACCENT_DARK, C, GENERAL_WEAPONS, HAIR, HAIR_DARK, OFFICER_FRAMES, OFFICER_TIERS,
                        TEAM, TEAM_DARK, TEAM_LIGHT, WALK_LIFT, general_weapon, guandao_turned, save_sheet, sheet,
                        split_layers)
from pixel import Canvas, hex_color

W, H = 32, 36
# Sparring rivals (M16j, Spar.RIVALS): wandering fighters with their own colors, not a side's.
NPC_FIGHTERS = ("ronin", "mace", "fist", "heroine", "spear")
N = {
    "slate": hex_color("5d6b7a"), "slate_dark": hex_color("3e4954"), "slate_light": hex_color("8495a6"),
    "vest": hex_color("7a4a2a"), "vest_dark": hex_color("513019"),
    "gi": hex_color("c98f4a"), "gi_dark": hex_color("93622e"), "gi_light": hex_color("e8b878"),
    "red": hex_color("b8281e"), "red_dark": hex_color("7e1a14"), "red_light": hex_color("e0584a"),
    "green": hex_color("4c7a4a"), "green_dark": hex_color("30522f"), "green_light": hex_color("71a06a"),
    "white_hair": hex_color("e9e6e0"), "white_hair_dark": hex_color("b4aea4"), "black_belt": hex_color("2a2420"),
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


def _tunic(c: Canvas, top: int, fill, dark, light, wide: bool = False) -> None:
    """A plain fighter's tunic from the shoulders (`top`) with a short skirt and a belt."""
    x0 = 10 if wide else 11
    c.rect(x0, top, 18 - x0, 9, fill)
    c.vline(x0, top, top + 8, dark)
    c.vline(16, top + 1, top + 5, light)
    c.rect(10, top + 8, 9, 4, dark)


def _fists(c: Canvas, state: str, frame: int, top: int, sleeve) -> None:
    """Bare hands: a fist in guard, a straight punch while attacking, raised while cheering."""
    if state == "attack":
        reach = (-1, 1, 5, 3)[frame]
        if reach > 0:
            c.hline(17, 17 + reach, top + 3, sleeve)
        c.rect(18 + reach, top + 2, 2, 2, C["skin"])
        c.px(19 + reach, top + 2, C["skin_dark"])
    elif state == "cheer":
        up = frame % 2
        c.vline(18, top - 3 - up, top + 1, sleeve)
        c.rect(18, top - 5 - up, 2, 2, C["skin"])
    else:
        c.vline(17, top + 2, top + 4, sleeve)
        c.rect(18, top + 3, 2, 2, C["skin"])


def npc_frame(state: str, frame: int, kind: str) -> tuple:
    """A sparring rival on foot (NPC_FIGHTERS): a swordsman under a wide bamboo hat, a bald mace
    master with a red headband, an old bare-handed master in an ochre gi, a heroine in red with a
    sword, a wanderer in green with a spear. Hair in the hair layer (but the master's white)."""
    c = Canvas(W, H)
    lift, fallen = _pose(state, frame)
    top = 16 - lift
    hy = top - 6
    if kind == "ronin":
        _legs(c, state, frame, lift, False)
        _tunic(c, top, N["slate"], N["slate_dark"], N["slate_light"])
        c.hline(11, 17, top + 7, C["belt"])
        c.vline(10, top + 1, top + 5, N["slate_dark"])
        _head(c, hy, False, frame)
        for y in range(hy + 2, hy + 6):  # a tail of hair under the hat
            c.px(11, y, HAIR if y < hy + 4 else HAIR_DARK)
        for row, half in enumerate((1, 2, 4, 5, 7)):  # nón tre: a wide flat cone over the eyes
            y = hy - 3 + row
            c.hline(14 - half, 14 + half, y, C["straw"] if row < 4 else C["straw_dark"])
        c.px(13, hy - 2, C["straw_dark"])
        c.px(16, hy, C["straw_dark"])
        c.vline(12, hy + 2, hy + 4, C["straw_dark"])  # chin strap
        _weapon(c, state, frame, top, "kiem")
    elif kind == "mace":
        _legs(c, state, frame, lift, False)
        c.rect(10, top, 8, 9, C["skin"])  # bare chest under an open vest
        c.vline(10, top, top + 8, C["skin_dark"])
        c.rect(10, top, 2, 8, N["vest"])
        c.rect(16, top, 2, 8, N["vest_dark"])
        c.px(14, top + 3, C["skin_dark"])
        c.rect(10, top + 8, 9, 4, N["vest_dark"])
        c.hline(10, 18, top + 7, N["red"])
        c.vline(9, top + 1, top + 5, C["skin_dark"])
        _head(c, hy, False, frame)
        c.hline(12, 15, hy - 1, C["skin"])  # bald, with a red headband and its tails
        c.hline(12, 15, hy, N["red"])
        c.px(11, hy + 1, N["red"])
        c.px(10 - frame % 2, hy + 2, N["red_dark"])
        c.hline(13, 15, hy + 4, HAIR)  # a short beard
        c.px(14, hy + 5, HAIR_DARK)
        _weapon(c, state, frame, top, "chuy")
    elif kind == "fist":
        _legs(c, state, frame, lift, False)
        _tunic(c, top, N["gi"], N["gi_dark"], N["gi_light"])
        for i in range(5):  # crossed collar
            c.px(14 - i // 2, top + i, N["gi_dark"])
        c.hline(11, 17, top + 7, N["black_belt"])
        c.px(11, top + 8, N["black_belt"])
        c.vline(10, top + 1, top + 5, N["gi_dark"])
        _head(c, hy, False, frame)
        c.hline(12, 15, hy - 1, N["white_hair"])  # white hair in a topknot, a long white beard
        c.rect(12, hy - 3, 2, 2, N["white_hair"])
        c.vline(12, hy, hy + 2, N["white_hair_dark"])
        c.px(16, hy + 1, N["white_hair"])  # bushy brow
        sway = (0, 0, 1, 1)[frame]
        for y in range(hy + 4, hy + 8):
            c.hline(14, 15 - (y - hy - 4) // 2, y, N["white_hair"] if y < hy + 6 else N["white_hair_dark"])
        c.px(14 + sway, hy + 8, N["white_hair_dark"])
        _fists(c, state, frame, top, N["gi"])
    elif kind == "heroine":
        _legs(c, state, frame, lift, False)
        _tunic(c, top, N["red"], N["red_dark"], N["red_light"])
        c.hline(11, 17, top + 7, C["gold"])
        for y in range(top + 1, top + 9):  # a second sword sheathed across the back
            c.px(9 + (y - top) // 3, y, C["lacquer"])
        c.px(9, top, C["hilt"])
        c.vline(10, top + 1, top + 5, N["red_dark"])
        _head(c, hy, True, frame)
        c.hline(12, 15, hy - 1, HAIR)
        c.rect(11, hy - 3, 3, 2, HAIR)  # a high bun with a red ribbon
        c.px(10, hy - 2, N["red"])
        c.px(9, hy - 1 + frame % 2, N["red_light"])
        _weapon(c, state, frame, top, "kiem")
    else:  # spear
        _cape(c, top, frame, 9, N["green_dark"])
        _legs(c, state, frame, lift, False)
        _tunic(c, top, N["green"], N["green_dark"], N["green_light"])
        c.hline(11, 17, top + 7, C["belt"])
        c.vline(10, top + 1, top + 5, N["green_dark"])
        _head(c, hy, False, frame)
        c.hline(12, 15, hy - 1, HAIR)  # short hair under a headband
        c.vline(11, hy - 1, hy + 2, HAIR_DARK)
        c.hline(12, 15, hy, C["feather"])
        c.px(10 - frame % 2, hy + 1, C["feather_dark"])
        _weapon(c, state, frame, top, "thuong")
    return split_layers(_fall(c) if fallen else c)


def draw_all() -> None:
    """general_foot_<m|f>[_<weapon>]_t<tier> (GameArt.foot_sprite) and npc_<kind> (Spar.RIVALS)."""
    for gender, female in (("m", False), ("f", True)):
        for tier in OFFICER_TIERS:
            for weapon_type in GENERAL_WEAPONS:
                name = f"general_foot_{gender}" + (f"_{weapon_type}" if weapon_type else "") + f"_t{tier}"
                save_sheet(name, sheet(lambda s, f, fe=female, w=weapon_type, ti=tier:
                                       general_foot_frame(s, f, fe, w, ti), W, H, OFFICER_FRAMES))
    for kind in NPC_FIGHTERS:
        save_sheet(f"npc_{kind}", sheet(lambda s, f, k=kind: npc_frame(s, f, k), W, H, OFFICER_FRAMES))
