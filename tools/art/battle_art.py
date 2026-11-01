"""Battle art (GDD §13, M12b): soldier sprite sheets, the mounted bodyguard, battlefield
backgrounds and effects. Called by generate.py.

Every sprite sheet has 2 columns (frames) and one row per state, in STATES order. Each sheet comes
with a "_team" sheet holding only the clothing in grays: the game draws it tinted with the side's
color (the player's color, the clan's banner color, bandit brown), so one drawing serves every side.
Sprites face right; the game mirrors them for the right-hand side.

A new unit type only needs an entry in SOLDIERS (or its own drawing function like the cavalry).
"""

import random

from PIL import Image

from pixel import CLEAR, P, Canvas, hex_color, speckle_area

STATES = ["stand", "walk", "attack", "fall", "cheer"]
FRAMES = 2

# Marker colors for clothing while drawing; split into the team sheet afterwards.
TEAM = hex_color("ff00ff")
TEAM_DARK = hex_color("800080")
TEAM_LIGHT = hex_color("ff80ff")
TEAM_GRAYS = {TEAM: hex_color("e0e0e0"), TEAM_DARK: hex_color("8e8e8e"), TEAM_LIGHT: hex_color("ffffff")}
# Officers also have a hair layer and an accent layer (plume, hat band, hairpin), tinted from
# their OfficerLook.
HAIR = hex_color("00ffff")
HAIR_DARK = hex_color("008080")
ACCENT = hex_color("ffff00")
ACCENT_DARK = hex_color("808000")
HAIR_GRAYS = {HAIR: hex_color("d8d8d8"), HAIR_DARK: hex_color("8a8a8a")}
ACCENT_GRAYS = {ACCENT: hex_color("e8e8e8"), ACCENT_DARK: hex_color("9a9a9a")}
LAYER_SUFFIXES = ["", "_team", "_hair", "_accent"]

C = {
    "skin": hex_color("f2c9a0"), "skin_dark": hex_color("d39b72"), "eye": hex_color("2b1d14"),
    "pants": hex_color("4a3424"), "belt": hex_color("3b2617"), "hair": hex_color("2e1e14"),
    "straw": hex_color("e2c26e"), "straw_dark": hex_color("b18c3e"),
    "iron": hex_color("7d8796"), "iron_light": hex_color("b9c2cf"),
    "steel": hex_color("dde3ea"), "hilt": hex_color("c9932e"),
    "shaft": hex_color("8a5a32"), "bow": hex_color("a36a3a"), "string": hex_color("efe6d2"),
    "band": hex_color("a8322a"), "club": hex_color("7a5230"),
    "horse": hex_color("8a5a34"), "horse_dark": hex_color("5e3b22"), "mane": hex_color("2e1e14"),
    "plume": hex_color("d23a2a"), "gold": hex_color("f2c23c"), "gold_dark": hex_color("b9862a"),
    "gold_light": hex_color("fff0a0"), "tassel": hex_color("c42a22"), "quiver": hex_color("7a4a28"),
    "feather": hex_color("f6f1e4"), "feather_dark": hex_color("c9bfa8"), "hat_black": hex_color("26201c"),
    "boot": hex_color("2b1d14"), "pheasant": hex_color("c8642a"), "pheasant_dark": hex_color("7a3a1e"),
    "lacquer": hex_color("8e2a1e"), "steel_edge": hex_color("ffffff"), "steel_dark": hex_color("9aa4b2"),
    "iron_dark": hex_color("4e5662"),
}

# The commander's sprite per worn weapon type (Item.WEAPON_TYPES; "" = a plain sword).
GENERAL_WEAPONS = ["", "dao", "thuong", "kiem", "kich", "chuy"]

# Each soldier type: weapon, headgear, gear (one or a tuple) and whether the clothes are rags
# (bandits). Tiers (GDD §8, M13): peasants wear straw hats, elites iron helmets and lamellar,
# royal guards gold-rimmed helmets with a tall plume and gold-trimmed armor.
SOLDIERS = {
    "swordsman": {"weapon": "sword", "hat": "conical", "gear": "pauldron"},
    "elite_swordsman": {"weapon": "sword", "hat": "helmet", "gear": ("lamellar", "pauldron")},
    "royal_swordguard": {"weapon": "sword", "hat": "royal", "gear": ("royal", "pauldron")},
    "spearman": {"weapon": "spear", "hat": "conical", "gear": "scale"},
    "elite_spearman": {"weapon": "spear", "hat": "helmet", "gear": "lamellar"},
    "royal_pikeguard": {"weapon": "pike", "hat": "royal", "gear": "royal"},
    "shield_peasant": {"weapon": "dao_shield", "hat": "headband", "gear": ""},
    "shield_veteran": {"weapon": "dao_shield", "hat": "helmet", "gear": "scale"},
    "shield_guard": {"weapon": "dao_shield", "hat": "royal", "gear": "royal"},
    "archer": {"weapon": "bow", "hat": "conical", "gear": "quiver"},
    "elite_archer": {"weapon": "bow", "hat": "helmet", "gear": ("quiver", "scale")},
    "marksman_archer": {"weapon": "bow", "hat": "feather_cap", "gear": ("quiver", "lamellar")},
    "crossbow_peasant": {"weapon": "crossbow", "hat": "conical", "gear": "bolts"},
    "crossbow_pro": {"weapon": "crossbow", "hat": "helmet", "gear": ("bolts", "scale")},
    "crossbow_elite": {"weapon": "crossbow", "hat": "royal", "gear": ("bolts", "lamellar")},
    "elite_musketeer": {"weapon": "musket", "hat": "jingasa", "gear": ("lamellar", "pauldron")},
    # Monks (M16f): shaved heads and robes; prayer beads from the elite tier, a gold-trimmed kasaya
    # and a ringed khakkhara staff for the royal tier.
    "monk": {"weapon": "staff", "hat": "shaved", "gear": "sash"},
    "elite_monk": {"weapon": "staff", "hat": "shaved", "gear": ("sash", "beads")},
    "royal_monk": {"weapon": "ring_staff", "hat": "shaved", "gear": ("kasaya", "beads")},
    "bandit_thug": {"weapon": "club", "hat": "headband", "rags": True},
    "bandit_archer": {"weapon": "bow", "hat": "headband", "rags": True},
}


class Pose:
    """Where the parts go for one frame of one state."""

    def __init__(self, state: str, frame: int):
        self.state = state
        self.frame = frame
        self.lift = 0  # whole body up (walk bob, cheer jump)
        if state == "walk" and frame == 1:
            self.lift = 1
        if state == "cheer" and frame == 1:
            self.lift = 1
        if state == "stand" and frame == 1:
            self.lift = 0


def legs(c: Canvas, pose: Pose) -> None:
    if pose.state == "walk":
        xs = (5, 9) if pose.frame == 0 else (7, 8)
    elif pose.state == "attack" and pose.frame == 1:
        xs = (5, 9)
    elif pose.state == "fall":
        xs = (6, 10)
    else:
        xs = (6, 9)
    for x in xs:
        c.vline(x, 12 - pose.lift, 14, C["pants"])
        c.px(x + 1, 15 - (1 if pose.lift and x == xs[0] else 0), C["belt"])
        c.px(x, 15 - (1 if pose.lift and x == xs[0] else 0), C["belt"])


def torso(c: Canvas, pose: Pose, rags: bool, gear="") -> None:
    gears = (gear,) if isinstance(gear, str) else tuple(gear)
    top = 7 - pose.lift
    breathe = 1 if pose.state == "stand" and pose.frame == 1 else 0
    if "quiver" in gears:  # on the back, arrows sticking out
        c.rect(4, top - 1, 2, 5, C["quiver"])
        c.px(4, top - 2, C["feather"])
        c.px(5, top - 3, C["feather"])
    if "bolts" in gears:  # a short bolt case on the hip
        c.rect(3, top + 3, 2, 3, C["quiver"])
        c.px(3, top + 2, C["iron_light"])
        c.px(4, top + 2, C["iron_light"])
    c.rect(5, top + breathe, 5, 5 - breathe, TEAM)
    c.vline(5, top + breathe, top + 4, TEAM_DARK)
    c.vline(8, top + breathe, top + 2, TEAM_LIGHT)
    c.hline(5, 9, top + 3, C["belt"])
    c.px(7, top + 3, C["gold_dark"])
    if "scale" in gears:  # scale armor over the chest
        for x, y in ((6, top + 1), (8, top + 1), (7, top + 2), (9, top + 2)):
            c.px(x, y + breathe, C["iron"])
        c.px(7, top + 1 + breathe, C["iron_light"])
    if "lamellar" in gears or "royal" in gears:  # rows of iron plates over the whole chest
        for y in (top + 1, top + 2):
            c.hline(6, 9, y + breathe, C["iron"])
        c.px(7, top + 1 + breathe, C["iron_light"])
        c.px(9, top + 2 + breathe, C["iron_dark"])
    if "royal" in gears:  # gold trim and buckle
        c.hline(5, 9, top + 3, C["gold_dark"])
        c.px(7, top + 3, C["gold"])
        c.px(9, top + breathe, C["gold"])
        c.px(5, top + breathe, C["gold"])
    if "sash" in gears:  # a dark sash from the shoulder across the robe
        for i in range(3):
            c.px(9 - i, top + i + breathe, C["belt"])
    if "kasaya" in gears:  # a gold-trimmed red kasaya draped over one shoulder
        for i in range(4):
            c.px(9 - i, top + i + breathe, C["lacquer"])
            c.px(8 - i, top + i + breathe, C["gold"])
    if "beads" in gears:  # a string of big prayer beads across the chest
        bead, bead_dark = (C["gold"], C["gold_dark"]) if "kasaya" in gears else (C["hilt"], C["club"])
        for x in range(6, 10):
            c.px(x, top + 1 + breathe, bead if x % 2 == 0 else bead_dark)
    if "pauldron" in gears:
        c.px(9, top + breathe, C["gold"] if "royal" in gears else C["iron"])
        c.px(9, top + 1 + breathe, C["iron"])
    if rags:
        for x in (5, 7, 9):
            c.px(x, top + 5, TEAM_DARK)
        c.px(8, top + 1, TEAM_DARK)


def head(c: Canvas, pose: Pose, hat: str) -> None:
    top = 3 - pose.lift + (1 if pose.state == "stand" and pose.frame == 1 else 0)
    c.rect(6, top, 4, 4, C["skin"])
    c.vline(6, top, top + 3, C["skin_dark"])
    c.px(9, top + 2, C["eye"])
    if hat == "conical":
        for row, (x0, x1) in enumerate(((7, 8), (6, 9), (5, 10), (4, 11))):
            c.hline(x0, x1, top - 3 + row, C["straw"])
        c.hline(4, 11, top, C["straw_dark"])
        c.px(7, top - 2, C["feather"])
        c.vline(5, top + 1, top + 2, C["straw_dark"])  # chin strap
    elif hat == "helmet":
        c.hline(6, 9, top - 1, C["iron"])
        c.hline(6, 9, top, C["iron"])
        c.px(5, top + 1, C["iron"])
        c.px(7, top - 1, C["iron_light"])
        c.px(8, top - 2, C["plume"])
    elif hat == "royal":  # iron helmet with a gold rim and a tall red plume
        c.hline(6, 9, top - 1, C["iron"])
        c.hline(6, 9, top, C["gold"])
        c.px(5, top + 1, C["iron"])
        c.px(7, top - 1, C["iron_light"])
        c.vline(8, top - 4, top - 2, C["plume"])
        c.px(7, top - 4, C["plume"])
    elif hat == "feather_cap":  # a dark cap with a long pheasant feather (marksmen)
        c.hline(6, 9, top - 1, C["hat_black"])
        c.hline(6, 9, top, C["hat_black"])
        c.px(9, top, C["gold"])
        for i in range(4):
            c.px(5 - i // 2, top - 2 - i, C["pheasant"] if i % 2 == 0 else C["pheasant_dark"])
    elif hat == "jingasa":  # flat, wide black lacquered hat with a gold crest (musketeers)
        c.hline(4, 11, top, C["hat_black"])
        c.hline(6, 9, top - 1, C["hat_black"])
        c.px(7, top - 2, C["gold"])
        c.px(8, top - 1, C["lacquer"])
    elif hat == "shaved":  # a monk's shaved head: a shine on the scalp
        c.px(8, top, C["feather"])
    elif hat == "headband":
        c.hline(6, 9, top, C["hair"])
        c.hline(6, 9, top + 1, C["band"])
        c.px(5, top + 1, C["band"])
        c.px(4, top + 2, C["band"])


def hand(c: Canvas, x: int, y: int) -> None:
    c.px(x, y, C["skin"])


def weapon(c: Canvas, pose: Pose, kind: str) -> None:
    lift = pose.lift
    state, frame = pose.state, pose.frame
    if state == "fall":
        hand(c, 4, 6 - lift)
        hand(c, 11, 5 - lift)
        return
    # Weapons stay one pixel inside the frame so their outline (and tips) are never cut off.
    if kind == "sword":
        if state == "attack" and frame == 0:
            c.vline(8, 1, 4, C["steel"])
            c.px(8, 5, C["hilt"])
            hand(c, 8, 6)
        elif state == "attack":
            c.hline(11, 14, 9, C["steel"])
            c.px(10, 9, C["hilt"])
            hand(c, 9, 9)
        elif state == "cheer":
            c.vline(10, 1, 2, C["steel"])
            c.px(10, 3, C["hilt"])
            hand(c, 10, 4)
        else:
            c.vline(11, 4 - lift, 8 - lift, C["steel"])
            c.hline(10, 12, 9 - lift, C["hilt"])
            hand(c, 11, 10 - lift)
    elif kind in ("spear", "pike"):
        # The royal pike has a red tassel under its blade.
        if state == "attack":
            x0 = 1 if frame == 0 else 4
            c.hline(x0, x0 + 8, 9, C["shaft"])
            c.hline(x0 + 9, x0 + 10, 9, C["steel"])
            c.px(x0 + 9, 8, C["steel"])
            if kind == "pike":
                c.px(x0 + 8, 10, C["tassel"])
            hand(c, x0 + 6, 10)
        else:
            top = 1 if state == "cheer" else 2 - lift
            c.vline(11, top + 2, 14 - lift - (2 if state == "cheer" else 0), C["shaft"])
            c.vline(11, top, top + 1, C["steel"])
            if kind == "pike":
                c.px(12, top + 2, C["tassel"])
            hand(c, 11, 8 - lift - (2 if state == "cheer" else 0))
    elif kind == "dao_shield":
        # A round wooden shield with an iron rim and boss in front, a broad dao in the other hand.
        sy = 7 - lift
        c.rect(10, sy, 3, 6, C["shaft"])
        c.vline(13, sy + 1, sy + 4, C["iron"])
        c.hline(10, 12, sy, C["iron"])
        c.hline(10, 12, sy + 5, C["iron"])
        c.px(11, sy + 2, C["iron_light"])
        c.px(11, sy + 3, C["gold_dark"])
        if state == "attack" and frame == 0:
            c.vline(7, 1, 4, C["steel"])
            c.px(6, 1, C["steel"])
            c.px(7, 5, C["hilt"])
            hand(c, 7, 6)
        elif state == "attack":
            c.hline(12, 14, 4, C["steel"])
            c.px(14, 3, C["steel"])
            c.px(11, 5, C["hilt"])
            hand(c, 10, 6)
        elif state == "cheer":
            c.vline(5, 1, 3, C["steel"])
            c.px(4, 1, C["steel"])
            hand(c, 5, 4)
        else:
            c.vline(4, 8 - lift, 11 - lift, C["steel"])
            c.px(3, 11 - lift, C["steel"])
            hand(c, 4, 7 - lift)
    elif kind == "crossbow":
        if state == "cheer":
            c.hline(8, 12, 2, C["shaft"])
            c.vline(12, 1, 3, C["bow"])
            hand(c, 10, 3)
            return
        y = 9 - lift
        if state == "attack" and frame == 1:  # recoil
            c.hline(7, 11, y, C["shaft"])
            c.vline(12, y - 2, y + 2, C["bow"])
        else:
            c.hline(8, 12, y, C["shaft"])
            c.vline(13, y - 2, y + 2, C["bow"])
            if state == "attack":  # string drawn back, bolt loaded
                c.px(12, y - 1, C["string"])
                c.px(12, y + 1, C["string"])
                c.px(14, y, C["steel"])
        hand(c, 9, y + 1)
    elif kind == "musket":
        if state == "attack":  # aimed: long barrel forward, a flash on the second frame
            c.hline(6, 10, 8, C["shaft"])
            c.hline(11, 13, 8, C["iron_dark"])
            hand(c, 8, 9)
            hand(c, 11, 9)
            if frame == 1:
                c.px(14, 8, C["gold_light"])
                c.px(14, 7, C["gold"])
        elif state == "cheer":
            c.vline(11, 1, 6, C["shaft"])
            c.vline(11, 1, 2, C["iron_dark"])
            hand(c, 11, 4)
        else:
            c.vline(11, 3 - lift, 14 - lift, C["shaft"])
            c.vline(11, 3 - lift, 6 - lift, C["iron_dark"])
            c.px(11, 2 - lift, C["steel"])  # bayonet
            hand(c, 11, 9 - lift)
    elif kind == "bow":
        if state == "cheer":
            c.hline(7, 12, 1, C["bow"])
            c.px(6, 2, C["bow"])
            c.px(13, 2, C["bow"])
            hand(c, 10, 3)
            return
        y = 5 - lift
        c.px(11, y, C["bow"])
        c.vline(12, y + 1, y + 6, C["bow"])
        c.px(11, y + 7, C["bow"])
        drawn = state == "attack" and frame == 0
        string_x = 9 if drawn else 11
        c.vline(string_x, y + 1, y + 6, C["string"])
        if drawn:
            c.hline(9, 13, y + 3, C["shaft"])
            c.px(14, y + 3, C["steel"])
        hand(c, 12, y + 3)
        hand(c, string_x, y + 3)
    elif kind in ("staff", "ring_staff"):
        # A long wooden staff with iron-banded ends; the khakkhara has gold rings at the top.
        ringed = kind == "ring_staff"
        if state == "attack":  # a two-handed sweep / thrust
            x0 = 1 if frame == 0 else 4
            y = 8 if frame == 0 else 9
            c.hline(x0, x0 + 10, y, C["shaft"])
            c.px(x0, y, C["iron"])
            c.px(x0 + 10, y, C["gold"] if ringed else C["iron"])
            if ringed:
                c.px(x0 + 10, y - 1, C["gold_light"])
                c.px(x0 + 10, y + 1, C["gold_dark"])
            hand(c, x0 + 4, y + 1)
            hand(c, x0 + 7, y + 1)
        else:
            top = 1 if state == "cheer" else 2 - lift
            c.vline(11, top, 14 - lift - (2 if state == "cheer" else 0), C["shaft"])
            c.px(11, top, C["gold"] if ringed else C["iron"])
            if ringed:
                c.px(10, top + 1, C["gold_light"])
                c.px(12, top + 1, C["gold_light"])
            hand(c, 11, 8 - lift - (2 if state == "cheer" else 0))
    elif kind == "club":
        if state == "attack" and frame == 0:
            c.rect(6, 1, 2, 3, C["club"])
            hand(c, 7, 5)
        elif state == "attack":
            c.hline(11, 14, 10, C["club"])
            c.hline(13, 14, 9, C["club"])
            hand(c, 10, 10)
        elif state == "cheer":
            c.rect(10, 1, 2, 2, C["club"])
            hand(c, 10, 3)
        else:
            c.vline(12, 5 - lift, 8 - lift, C["club"])
            c.vline(13, 5 - lift, 6 - lift, C["club"])
            hand(c, 11, 9 - lift)


def split_team(full: Canvas) -> tuple:
    """Outline the whole figure, then separate the clothing into its own grayscale sheet."""
    full.outline()
    base = Canvas(full.width, full.height)
    team = Canvas(full.width, full.height)
    for y in range(full.height):
        for x in range(full.width):
            color = full.get(x, y)
            if color in TEAM_GRAYS:
                team.px(x, y, TEAM_GRAYS[color])
            elif color[3]:
                base.px(x, y, color)
    return base, team


def split_layers(full: Canvas) -> tuple:
    """Like split_team, plus the hair and accent layers of an officer sprite."""
    full.outline()
    layers = [Canvas(full.width, full.height) for _ in LAYER_SUFFIXES]
    for y in range(full.height):
        for x in range(full.width):
            color = full.get(x, y)
            if color in TEAM_GRAYS:
                layers[1].px(x, y, TEAM_GRAYS[color])
            elif color in HAIR_GRAYS:
                layers[2].px(x, y, HAIR_GRAYS[color])
            elif color in ACCENT_GRAYS:
                layers[3].px(x, y, ACCENT_GRAYS[color])
            elif color[3]:
                layers[0].px(x, y, color)
    return tuple(layers)


def soldier_frame(spec: dict, state: str, frame: int) -> tuple:
    pose = Pose(state, frame)
    c = Canvas(16, 16)
    legs(c, pose)
    torso(c, pose, spec.get("rags", False), spec.get("gear", ""))
    head(c, pose, spec["hat"])
    weapon(c, pose, spec["weapon"])
    return split_team(c)


def cavalry_frame(state: str, frame: int, variant: str = "guard", weapon: str = "lance") -> tuple:
    """A rider of the commander's bodyguard (24×22, headroom above): a horse with a saddle cloth
    and breast strap in the side's color, the rider in iron lamellar over a colored coat, an iron
    helmet with a red tassel, and a lance with a pennant in the side's color.
    Variants (GDD §8, M13): "guard" (the bodyguard and lancers), "light" (a cloth cap, no armor, no
    pennant), "heavy" (iron barding on the horse's chest and face, a plumed helmet), "royal" (a
    gold-rimmed helmet with a tall plume, gold trim on the saddle cloth).
    weapon "bow" (horse archers, M16f): a recurve bow instead of the lance and a quiver at the
    rider's back."""
    c = Canvas(24, 22)
    gallop = state in ("walk", "attack") and frame == 1
    lift = 1 if (state == "cheer" or state == "walk") and frame == 1 else 0
    # Tail and legs.
    for y, x in ((12, 4), (13, 3), (14, 3), (15, 3 + frame)):
        c.px(x, y, C["mane"])
    legs_x = (6, 9, 14, 17) if not gallop else (5, 10, 13, 18)
    for i, x in enumerate(legs_x):
        bend = 1 if gallop and i in (0, 3) else 0
        c.vline(x, 17, 20 - bend, C["horse_dark"] if i in (1, 2) else C["horse"])
        c.px(x, 21 - bend, C["boot"])
    # Body, neck reaching forward, head.
    c.rect(5, 12, 13, 5, C["horse"])
    c.hline(6, 17, 16, C["horse_dark"])
    for row, x0 in enumerate((16, 17, 17, 18)):
        c.hline(x0, x0 + 2, 12 - row, C["horse"])
    c.rect(18, 7, 4, 3, C["horse"])
    c.rect(20, 8, 3, 2, C["horse"])
    c.px(22, 9, C["horse_dark"])
    c.px(20, 7, C["eye"])
    c.px(19, 6, C["horse_dark"])
    for y in range(8, 13):
        c.px(16 + (y - 8) // 2, y, C["mane"])
    c.vline(17, 10, 12, TEAM)  # breast strap
    if variant == "heavy":  # iron barding over the chest and a face plate
        c.rect(15, 10, 3, 5, C["iron"])
        c.vline(15, 10, 14, C["iron_dark"])
        c.px(16, 11, C["iron_light"])
        c.hline(19, 21, 7, C["iron"])
        c.px(20, 7, C["iron_light"])
    # Saddle cloth with a dark hem.
    c.rect(7, 11, 7, 4, TEAM)
    c.hline(7, 13, 11, TEAM_LIGHT)
    c.hline(7, 13, 14, TEAM_DARK)
    c.px(7, 15, C["tassel"])
    c.px(13, 15, C["tassel"])
    if variant == "royal":
        c.hline(7, 13, 14, C["gold"])
    # Rider: colored coat under iron lamellar.
    top = 5 - lift
    if weapon == "bow":  # the quiver at the rider's back, feathers up
        c.rect(7, top, 2, 4, C["quiver"])
        c.px(7, top - 1, C["feather"])
        c.px(8, top - 2, C["feather"])
    c.rect(9, top, 4, 6, TEAM)
    c.vline(9, top, top + 5, TEAM_DARK)
    if variant != "light":
        for y in (top + 1, top + 3):
            c.hline(10, 12, y, C["iron"])
        c.px(11, top + 2, C["iron_light"])
    c.hline(9, 12, top + 4, C["belt"])
    c.rect(9, top - 4, 4, 4, C["skin"])
    c.vline(9, top - 4, top - 1, C["skin_dark"])
    c.px(12, top - 2, C["eye"])
    if variant == "light":  # a cloth cap in the side's color
        c.hline(9, 12, top - 4, TEAM_DARK)
        c.hline(10, 11, top - 5, TEAM)
    else:
        c.hline(8, 13, top - 4, C["iron"])
        c.hline(9, 12, top - 5, C["iron"])
        c.px(10, top - 5, C["iron_light"])
        c.px(8, top - 3, C["iron_dark"])
        c.px(11, top - 6, C["tassel"])
        c.px(10, top - 7, C["tassel"])
        if variant == "heavy":
            c.px(12, top - 6, C["plume"])
            c.px(12, top - 7, C["plume"])
        if variant == "royal":
            c.hline(8, 13, top - 4, C["gold"])
            c.vline(12, top - 8, top - 6, C["plume"])
    if weapon == "bow":
        _rider_bow(c, state, frame, top)
        return split_team(c)
    # Lance with a pennant.
    if state == "attack" and frame == 1:
        c.hline(12, 21, top + 2, C["shaft"])
        c.hline(22, 23, top + 2, C["steel"])
        if variant != "light":
            c.rect(18, top, 3, 2, TEAM)
        c.px(13, top + 3, C["skin"])
    elif state == "attack":
        for i in range(8):
            c.px(13 - i // 2, top + 3 - i, C["shaft"])
        c.px(9, top - 5, C["steel"])
        c.px(13, top + 3, C["skin"])
    elif state == "fall":
        c.hline(1, 8, top + 1, C["shaft"])
    else:
        lance_top = max(0, top - 4 - (2 if state == "cheer" else 0))
        c.vline(14, lance_top + 2, 15, C["shaft"])
        c.vline(14, lance_top, lance_top + 1, C["steel"])
        flutter = frame
        if variant != "light":
            c.rect(15, lance_top + 2, 3 + flutter, 2, TEAM)
            c.px(17 + flutter, lance_top + 2, TEAM_DARK)
        c.px(13, top + 3, C["skin"])
    return split_team(c)


def _rider_bow(c: Canvas, state: str, frame: int, top: int) -> None:
    """A horse archer's bow held out in front of the rider: drawn with an arrow on the first attack
    frame, just loosed on the second; dropped on a fall."""
    if state == "fall":
        c.hline(2, 7, top + 2, C["bow"])
        return
    bx = 16 if state != "cheer" else 15
    by = top - 2 - (2 if state == "cheer" else 0)
    c.px(bx - 1, by, C["bow"])
    c.vline(bx, by + 1, by + 5, C["bow"])
    c.px(bx - 1, by + 6, C["bow"])
    drawn = state == "attack" and frame == 0
    string_x = bx - 3 if drawn else bx - 1
    c.vline(string_x, by + 1, by + 5, C["string"])
    if drawn:
        c.hline(string_x, bx + 2, by + 3, C["shaft"])
        c.px(bx + 3, by + 3, C["steel"])
    elif state == "attack":  # the arrow just left
        c.px(bx + 4, by + 3, C["shaft"])
        c.px(bx + 5, by + 3, C["steel"])
    c.px(bx, by + 3, C["skin"])
    c.px(string_x, by + 3, C["skin"])


# Cavalry sprite per unit (GDD §8, M13), drawn by cavalry_frame; horse archers (M16f) carry bows.
CAVALRY = {"light_cavalry": "light", "lancer_cavalry": "guard", "heavy_cavalry": "heavy"}
HORSE_ARCHERS = {"horse_archer": "light", "elite_horse_archer": "guard", "royal_horse_archer": "royal"}
# Artillery sprite per unit: barrel color, length and thickness.
ARTILLERY = {"light_artillery": ("gold_dark", 7, 2), "heavy_artillery": ("iron_dark", 9, 3)}


def artillery_frame(state: str, frame: int, barrel: str, length: int, thick: int) -> tuple:
    """A gunner (24×16) beside a field gun on a wooden carriage: bronze for light guns, a longer,
    thicker iron barrel for heavy ones. The attack frames fire (a flash, then the recoil)."""
    pose = Pose(state, frame)
    gunner = Canvas(16, 16)
    legs(gunner, pose)
    torso(gunner, pose, False, "")
    head(gunner, pose, "helmet")
    weapon(gunner, pose, "")
    c = Canvas(24, 16)
    c.paste(gunner, 0, 0)
    recoil = 1 if state == "attack" and frame == 1 else 0
    x0 = 13 - recoil
    # Carriage and wheel.
    c.hline(x0, x0 + 6, 11, C["shaft"])
    c.hline(x0 - 2, x0 + 1, 12, C["shaft"])
    c.ellipse(x0 + 4, 12.5, 2.6, 2.6, C["horse_dark"])
    c.px(x0 + 4, 12, C["gold_dark"])
    spoke = (0, 1) if (state == "walk" and frame == 1) else (1, 0)
    c.px(x0 + 4 + spoke[0], 12 - spoke[1], C["shaft"])
    # Barrel, tilted up a little.
    y = 10 - thick
    c.rect(x0, y, length, thick, C[barrel])
    c.hline(x0, x0 + length - 1, y, C["iron_light"] if barrel == "iron_dark" else C["gold"])
    c.vline(x0 + length, y - 1, y + thick - 1, C[barrel])
    if state == "attack" and frame == 0:
        mx = min(22, x0 + length + 1)
        c.vline(mx, y - 1, y + thick, C["gold_light"])
        c.px(mx, y + thick // 2, C["gold"])
    return split_team(c)


def general_frame(state: str, frame: int, female: bool = False, weapon_type: str = "") -> tuple:
    """The commander (32×32): a barded warhorse with a plated chamfron and red tassels, the rider
    in gilded armor with a flowing cape, a gold helmet with two long pheasant feathers, and the
    weapon they wear (general_weapon: a plain sword without one). Clothes, barding and cape take
    the side's color."""
    c = Canvas(32, 32)
    gallop = state in ("walk", "attack") and frame == 1
    lift = 1 if (state == "cheer" and frame == 1) or (state == "walk" and frame == 1) else 0
    # Tail and legs behind the body.
    for y, x in ((17, 7), (18, 6), (19, 5), (20, 5), (21, 5 + frame), (22, 6 + frame)):
        c.px(x, y, C["mane"])
        c.px(x + 1, y, C["mane"])
    legs_x = (10, 13, 19, 22) if not gallop else (9, 14, 18, 23)
    for i, x in enumerate(legs_x):
        bend = 1 if gallop and i in (0, 3) else 0
        c.vline(x, 23, 29 - bend, C["horse_dark"] if i in (1, 2) else C["horse"])
        c.vline(x + 1, 23, 29 - bend, C["horse_dark"])
        c.hline(x, x + 1, 30 - bend, C["boot"])
    # Body, a short arched neck and a small head (kept one pixel inside the frame for its outline).
    c.rect(8, 16, 16, 7, C["horse"])
    c.hline(9, 22, 22, C["horse_dark"])
    for row, x0 in enumerate((22, 22, 23, 23, 24)):  # neck rising forward
        c.hline(x0, x0 + 2, 16 - row, C["horse"])
    c.rect(24, 9, 4, 3, C["horse"])  # head
    c.rect(27, 10, 2, 3, C["horse"])  # muzzle
    c.px(29, 12, C["horse_dark"])
    c.hline(27, 28, 12, C["horse_dark"])
    c.px(26, 10, C["eye"])
    c.px(24, 8, C["horse_dark"])  # ears
    c.px(25, 8, C["horse_dark"])
    c.rect(24, 9, 2, 2, C["iron"])  # chamfron
    c.px(25, 9, C["iron_light"])
    for x, y in ((23, 10), (23, 11), (22, 12)):
        c.px(x, y, C["tassel"])
    for y in range(12, 17):  # mane along the neck
        c.px(21 + (y - 12) // 3, y, C["mane"])
    # Barding over the back and flanks: side color, scale pattern, gold hem and tassels.
    c.rect(9, 15, 13, 5, TEAM)
    for y in (16, 18):
        for x in range(10 + (y // 2) % 2, 21, 2):
            c.px(x, y, TEAM_DARK)
    c.hline(9, 21, 15, TEAM_LIGHT)
    c.hline(9, 21, 20, C["gold"])
    for x in (10, 15, 20):
        c.px(x, 21, C["tassel"])
    # Cape behind the rider (flutters).
    cape = ((10, 10), (9, 11), (9, 12), (8, 13), (8, 14)) if frame == 0 else ((10, 10), (9, 11), (8, 12), (7, 13), (7, 14))
    for x, y in cape:
        c.hline(x, 12, y - lift, TEAM_DARK)
    # Rider.
    top = 9 - lift
    c.rect(12, top, 6, 6, TEAM)
    c.vline(12, top, top + 5, TEAM_DARK)
    c.vline(16, top + 1, top + 3, TEAM_LIGHT)
    c.hline(12, 17, top + 4, C["gold"])
    c.hline(11, 13, top, C["gold"])
    c.hline(16, 18, top, C["gold"])
    c.px(17, top + 1, C["gold_dark"])
    c.rect(13, top - 4, 4, 4, C["skin"])
    c.vline(13, top - 4, top - 1, C["skin_dark"])
    c.px(16, top - 2, C["eye"])
    c.hline(12, 17, top - 5, C["gold"])
    c.hline(13, 16, top - 6, C["gold"])
    c.px(14, top - 6, C["gold_light"])
    c.px(12, top - 4, C["gold_dark"])
    # Two pheasant feathers sweeping back from the helmet (accent color).
    for i, (x, y) in enumerate(((13, top - 7), (12, top - 8), (11, top - 8), (10, top - 9), (9, top - 9), (8, top - 9))):
        c.px(x, y, ACCENT if i % 2 == 0 else ACCENT_DARK)
        c.px(x + 1, y + 1, ACCENT_DARK)
    if female:  # long hair flowing from under the helmet
        for y in range(top - 3, top + 4):
            c.hline(10 - (y - top) // 3 - frame, 12, y, HAIR if y < top + 2 else HAIR_DARK)
    # The weapon is drawn upright once (general_weapon) and placed or turned for each pose so its
    # proportions never change; `grip` is the row the hand holds.
    weapon, grip = general_weapon(weapon_type, frame)
    if state == "attack" and frame == 0:  # wind-up: raised behind the rider
        c.paste(weapon, 9, max(0, top + 1 - grip) if grip > 12 else 0)
        c.px(12, top + 1, C["skin"])
    elif state == "attack":  # swung forward, blade leading
        # The hand stays at x 18; the tip never reaches the right edge (room for the outline).
        c.paste(guandao_turned(weapon), max(1, min(18 - (weapon.height - 1 - grip), c.width - 1 - weapon.height)), top + 1)
        c.px(18, top + 2, C["skin"])
    else:
        hand_y = top + 3 - (2 if state == "cheer" else 0)
        c.paste(weapon, 18, max(0, hand_y - grip))
        c.px(19, hand_y, C["skin"])
    return split_layers(c)


def general_weapon(weapon_type: str, frame: int) -> tuple:
    """The commander's weapon upright, with the row the hand holds: a plain sword (none worn),
    or a đao / thương / kiếm / kích / chùy (Item.WEAPON_TYPES)."""
    if weapon_type == "dao":
        return guandao(frame), 9
    if weapon_type == "thuong":
        w = Canvas(5, 27)
        for y, (x0, x1) in enumerate(((2, 2), (1, 3), (1, 3), (1, 3), (2, 2))):  # leaf tip
            w.hline(x0, x1, y, C["steel"])
        w.px(3, 1, C["steel_edge"])
        w.vline(2, 5, 25, C["shaft"])
        for x, y in ((1, 6), (3, 6), (0, 7), (4, 7), (1 + frame, 8)):  # red tassel
            w.px(x, y, C["tassel"])
        w.px(2, 26, C["iron"])
        return w, 10
    if weapon_type == "kich":
        w = Canvas(6, 27)
        for y in range(4):
            w.px(2, y, C["steel"])
        w.px(3, 1, C["steel_edge"])
        for x, y in ((3, 5), (4, 4), (5, 5), (5, 6), (4, 7), (3, 7)):  # crescent side blade
            w.px(x, y, C["steel"])
        w.px(5, 5, C["steel_edge"])
        w.vline(2, 4, 25, C["lacquer"])
        w.px(1, 8, C["tassel"])
        w.px(1 - (frame == 1), 9, C["tassel"])
        w.px(2, 26, C["iron"])
        return w, 10
    if weapon_type == "chuy":
        w = Canvas(7, 18)
        w.ellipse(3.5, 3.0, 3.0, 3.0, C["iron"])
        w.ellipse(4.0, 3.6, 1.5, 1.5, C["iron_dark"])
        for x, y in ((3, 0), (0, 3), (6, 3), (3, 6)):
            w.px(x, y, C["iron_light"])
        w.vline(3, 6, 17, C["shaft"])
        w.px(3, 12, C["gold"])
        return w, 13
    if weapon_type == "kiem":
        w = Canvas(5, 17)
        w.vline(2, 0, 11, C["steel"])
        w.vline(3, 1, 11, C["steel_edge"])
        w.hline(0, 4, 12, C["gold"])
        w.vline(2, 13, 15, C["lacquer"])
        w.px(2, 16, C["gold"])
        w.px(1 + frame, 16, C["tassel"])
        return w, 14
    w = Canvas(5, 14)  # a plain sword
    w.vline(2, 0, 9, C["steel"])
    w.vline(3, 1, 9, C["steel_dark"])
    w.hline(1, 3, 10, C["hilt"])
    w.vline(2, 11, 13, C["belt"])
    return w, 12


def guandao(frame: int = 0) -> Canvas:
    """The commander's Thanh long đao, upright (6×27): a slim blade curving forward with a light
    edge and a back notch, a gold guard with a red tassel, a long red-lacquered shaft with gold
    bands, and an iron butt spike."""
    w = Canvas(6, 27)
    blade = ((3, 3), (3, 4), (2, 4), (2, 4), (2, 3), (1, 3), (1, 3), (1, 2))
    for y, (x0, x1) in enumerate(blade):
        for x in range(x0, x1 + 1):
            w.px(x, y, C["steel"])
        w.px(x1, y, C["steel_edge"])
        w.px(x0, y, C["steel_dark"])
    w.px(0, 5, C["steel"])  # back notch
    w.hline(0, 3, 8, C["gold"])
    w.px(1, 9, C["gold_dark"])
    w.vline(1, 10, 25, C["lacquer"])
    for y in (14, 20):
        w.px(1, y, C["gold"])
    w.px(1, 26, C["iron"])
    for x, y in ((2, 9), (3, 10), (3 + frame, 11), (2 + frame, 12)):
        w.px(x, y, C["tassel"])
    return w


def guandao_turned(weapon: Canvas) -> Canvas:
    """The glaive turned to point forward (to the right), for the slash."""
    turned = Canvas(weapon.height, weapon.width)
    turned.image = weapon.image.transpose(Image.Transpose.ROTATE_270)
    return turned


def advisor_frame(state: str, frame: int, female: bool = False) -> tuple:
    """A strategist (20×24): long robe with wide sleeves in the side's color, a black scholar's hat
    and a white feather fan they raise to cast a stratagem."""
    c = Canvas(20, 24)
    sway = 1 if state == "walk" and frame == 1 else 0
    # Robe.
    for row in range(11):
        half = 3 + row // 3
        c.hline(9 - half + sway * (row > 7), 10 + half + sway * (row > 7), 11 + row, TEAM)
    for row in range(11):
        half = 3 + row // 3
        c.px(9 - half, 11 + row, TEAM_DARK)
    c.hline(5, 14, 21, C["gold"])
    c.vline(10, 11, 14, C["feather"])  # white collar
    c.px(9, 11, C["feather"])
    c.px(11, 11, C["feather"])
    c.hline(7, 12, 15, TEAM_DARK)  # sash
    c.px(10, 16, TEAM_DARK)
    c.hline(7, 8, 23, C["boot"])
    c.hline(11, 12, 23, C["boot"])
    # Sleeve.
    c.rect(12, 12, 3, 4, TEAM_LIGHT)
    c.vline(12, 12, 15, TEAM)
    # Head and hat.
    c.rect(8, 6, 4, 5, C["skin"])
    c.vline(8, 6, 10, C["skin_dark"])
    c.px(11, 8, C["eye"])
    if female:
        c.rect(7, 4, 5, 3, HAIR)
        c.ellipse(9.5, 3, 2.2, 1.8, HAIR)
        c.vline(7, 6, 13, HAIR_DARK)  # long hair down the back
        c.vline(6, 8, 12, HAIR_DARK)
        c.hline(11, 14, 3, ACCENT)  # hairpin
        c.px(14, 2, ACCENT_DARK)
    else:
        c.rect(7, 3, 5, 3, C["hat_black"])  # winged official's cap
        c.hline(4, 6, 4, C["hat_black"])
        c.hline(13, 15, 4, C["hat_black"])
        c.hline(7, 11, 5, ACCENT)
        c.vline(7, 6, 8, HAIR)
    # Feather fan.
    if state == "attack" and frame == 0 or state == "cheer":
        fan = (13, 1)
        c.vline(14, 6, 11, C["gold_dark"])
    elif state == "attack":
        fan = (16, 7)
        c.hline(14, 16, 12, C["gold_dark"])
    else:
        fan = (14, 9)
        c.vline(15, 13, 15, C["gold_dark"])
    fx, fy = fan
    c.rect(fx, fy, 4, 4, C["feather"])
    c.px(fx + 3, fy, CLEAR)
    c.px(fx, fy + 3, C["feather_dark"])
    c.hline(fx, fx + 2, fy + 3, C["feather_dark"])
    c.px(fx + 1, fy + 1, C["feather_dark"])
    return split_layers(c)


def sheet(draw_frame, width: int, height: int) -> tuple:
    """All states and frames of one sprite, one sheet per layer (base, team, and for officers hair
    and accent)."""
    layers = None
    for row, state in enumerate(STATES):
        for frame in range(FRAMES):
            parts = draw_frame(state, frame)
            if layers is None:
                layers = [Canvas(width * FRAMES, height * len(STATES)) for _ in parts]
            for layer, part in zip(layers, parts):
                layer.paste(part, frame * width, row * height)
    return tuple(layers)


def save_sheet(name: str, layers: tuple) -> None:
    for layer, suffix in zip(layers, LAYER_SUFFIXES):
        layer.save(f"units/{name}{suffix}.png")


# --- Battlefield ----------------------------------------------------------------------------

def mountains() -> Canvas:
    """Far blue mountains and nearer green hills, tileable horizontally (64×24)."""
    c = Canvas(64, 24)
    far = hex_color("8fa7c4")
    near = hex_color("6f9a74")
    snow = hex_color("e9eef5")
    for x in range(64):
        peak = 4 + int(5 * abs(((x * 3) % 64) / 32 - 1))  # zigzag, period 64/3
        for y in range(peak, 24):
            c.px(x, y, far)
        if peak <= 5:
            c.px(x, peak, snow)
        hill = 13 + int(3 * abs(((x * 2 + 16) % 64) / 32 - 1))
        for y in range(hill, 24):
            c.px(x, y, near)
    return c


def cloud() -> Canvas:
    c = Canvas(24, 9)
    white = hex_color("fbfdff")
    c.ellipse(8, 5, 6, 3.6, white)
    c.ellipse(15, 4.5, 6.5, 4, white)
    c.hline(3, 21, 8, hex_color("dbe6f2"))
    return c


def battle_ground() -> Canvas:
    rng = random.Random(21)
    c = Canvas(32, 32, P["grass"])
    for _ in range(60):
        c.px(rng.randrange(32), rng.randrange(32), rng.choice([P["grass_dark"], P["grass_light"]]))
    for _ in range(8):
        x, y = rng.randrange(1, 30), rng.randrange(2, 31)
        c.px(x, y, P["grass_dark"])
        c.px(x + 1, y - 1, P["grass_dark"])
        c.px(x + 2, y, P["grass_dark"])
    return c


def town() -> Canvas:
    """The kingdom's walls and roofs behind the defenders (96×40)."""
    c = Canvas(96, 40)
    # Roofs and a pagoda behind the wall.
    for x0, w in ((6, 18), (30, 14), (60, 20)):
        c.rect(x0 + 2, 14, w - 4, 8, P["wall"])
        for row in range(4):
            c.hline(x0 + 3 - row, x0 + w - 4 + row, 10 + row, P["roof"] if row < 3 else P["roof_dark"])
    c.rect(44, 4, 12, 18, P["wall"])
    for top in (2, 9):
        for row in range(3):
            c.hline(42 + 2 - row, 57 - 2 + row, top + row, P["roof"] if row < 2 else P["roof_dark"])
    c.vline(50, 0, 1, P["red"])
    # Wall with battlements and a gate.
    c.rect(0, 22, 96, 18, P["stone"])
    for x in range(0, 96, 4):
        c.rect(x, 20, 2, 2, P["stone_light"])
    for y in (27, 32, 37):
        for x in range((y // 5 % 2) * 3, 96, 6):
            c.hline(x, x + 3, y, P["stone_dark"])
    c.rect(40, 28, 16, 12, P["door"])
    c.hline(42, 53, 27, P["door"])
    c.outline()
    return c


def camp() -> tuple:
    """An enemy camp behind the clan's army (96×40): tents striped and bannered in its colors."""
    c = Canvas(96, 40)
    canvas_color = hex_color("efe4c8")
    for x0, w, h in ((4, 20, 16), (30, 26, 20), (64, 22, 15)):
        for row in range(h):
            half = row * w // (2 * h)
            mid = x0 + w // 2
            c.hline(mid - half, mid + half, 40 - h + row, canvas_color)
        for row in range(h):
            half = row * w // (2 * h)
            c.px(x0 + w // 2 - half, 40 - h + row, TEAM_DARK)
            c.px(x0 + w // 2 + half, 40 - h + row, TEAM_DARK)
        c.vline(x0 + w // 2, 40 - h, 39, TEAM)
        c.rect(x0 + w // 2 - 1, 34, 3, 6, P["door"])
    for x in (20, 60, 90):
        c.vline(x, 8, 39, P["wood_dark"])
        c.rect(x + 1, 8, 6, 5, TEAM)
        c.px(x + 6, 12, TEAM_DARK)
    return split_team(c)


# --- Effects ----------------------------------------------------------------------------------

def fire(frame: int) -> Canvas:
    c = Canvas(12, 12)
    red, orange, yellow = hex_color("d8402a"), hex_color("f28a2e"), hex_color("ffd85a")
    shift = frame
    c.ellipse(6, 8, 5, 4, red)
    c.ellipse(6 + shift - 0.5, 6.5, 3.5, 4.5, orange)
    c.ellipse(6 - shift + 0.5, 7.5, 2, 3, yellow)
    c.px(4 + shift * 3, 1 + shift, orange)
    return c


def sparkle(frame: int) -> Canvas:
    c = Canvas(8, 8)
    gold, light = P["gold"], P["gold_light"]
    size = 3 if frame == 0 else 2
    c.hline(4 - size, 3 + size, 4, gold)
    c.vline(4, 4 - size, 3 + size, gold)
    c.px(4, 4, light)
    if frame == 1:
        c.px(1, 1, light)
        c.px(6, 6, light)
    return c


def smoke(frame: int) -> Canvas:
    c = Canvas(12, 12)
    gray, light = hex_color("7a7470"), hex_color("aaa39c")
    c.ellipse(6, 7 - frame, 4 + frame, 3.5 + frame * 0.5, gray)
    c.ellipse(5, 5 - frame, 2.5, 2.5, light)
    return c


def arrow() -> Canvas:
    c = Canvas(9, 3)
    c.hline(1, 6, 1, C["shaft"])
    c.px(7, 1, C["steel"])
    c.px(8, 1, C["steel"])
    c.px(0, 0, hex_color("f3eee2"))
    c.px(0, 2, hex_color("f3eee2"))
    c.px(1, 0, hex_color("f3eee2"))
    c.px(1, 2, hex_color("f3eee2"))
    return c


def strip(draw, frames: int) -> Canvas:
    first = draw(0)
    out = Canvas(first.width * frames, first.height)
    for f in range(frames):
        out.paste(draw(f), f * first.width, 0)
    return out


def draw_all() -> None:
    for name, spec in SOLDIERS.items():
        base, team = sheet(lambda state, frame, spec=spec: soldier_frame(spec, state, frame), 16, 16)
        base.save(f"units/{name}.png")
        team.save(f"units/{name}_team.png")
    base, team = sheet(cavalry_frame, 24, 22)
    base.save("units/general_guard.png")
    team.save("units/general_guard_team.png")
    for name, variant in CAVALRY.items():
        save_sheet(name, sheet(lambda s, f, v=variant: cavalry_frame(s, f, v), 24, 22))
    for name, variant in HORSE_ARCHERS.items():
        save_sheet(name, sheet(lambda s, f, v=variant: cavalry_frame(s, f, v, "bow"), 24, 22))
    for name, spec in ARTILLERY.items():
        save_sheet(name, sheet(lambda s, f, sp=spec: artillery_frame(s, f, *sp), 24, 16))
    for gender, female in (("m", False), ("f", True)):
        for weapon_type in GENERAL_WEAPONS:
            name = f"general_{gender}" + (f"_{weapon_type}" if weapon_type else "")
            save_sheet(name, sheet(lambda s, f, fe=female, w=weapon_type: general_frame(s, f, fe, w), 32, 32))
        save_sheet(f"advisor_{gender}", sheet(lambda s, f, fe=female: advisor_frame(s, f, fe), 20, 24))
    mountains().save("battle/mountains.png")
    cloud().save("battle/cloud.png")
    battle_ground().save("battle/ground.png")
    town().save("battle/town.png")
    camp_base, camp_team = camp()
    camp_base.save("battle/camp.png")
    camp_team.save("battle/camp_team.png")
    strip(fire, 2).save("effects/fire.png")
    strip(sparkle, 2).save("effects/sparkle.png")
    strip(smoke, 2).save("effects/smoke.png")
    arrow().save("effects/arrow.png")
