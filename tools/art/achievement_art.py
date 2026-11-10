"""Achievement medals (M18b, GDD §30): one 24×24 medal per category (Achievements.CATEGORIES),
saved ×2 to assets/icons/achievement_<category>.png, plus `achievement_secret` for a hidden one
not yet unlocked. Locked medals are grayed by the game (modulate), not drawn twice.

Run alone with `python tools/art/achievement_art.py`; generate.py calls draw_all() too."""

from pixel import P, UI_SCALE, Canvas, hex_color

S = 24
GOLD, GOLD_DARK, GOLD_LIGHT = P["gold"], P["gold_dark"], P["gold_light"]
RIBBONS = {
    "economy": (hex_color("4f9a3a"), hex_color("2f6a24")),
    "military": (P["red"], P["red_dark"]),
    "diplomacy": (hex_color("3e6fb0"), hex_color("2a4a7a")),
    "officers": (hex_color("6a3e9a"), hex_color("432463")),
    "adventure": (hex_color("c27a2a"), hex_color("8a5216")),
    "conquest": (hex_color("b0302a"), hex_color("6e1a16")),
    "secret": (hex_color("4a4f5c"), hex_color("2e323a")),
}
INK = hex_color("6b3e12")


def medal(category: str) -> Canvas:
    """A ribbon over a round gold medal; the category's sign in the middle."""
    c = Canvas(S, S)
    ribbon, ribbon_dark = RIBBONS[category]
    for y in range(0, 9):  # two ribbon tails
        c.hline(6 + y // 3, 9 + y // 3, y, ribbon)
        c.hline(14 - y // 3, 17 - y // 3, y, ribbon_dark)
    c.ellipse(11.5, 14.5, 8.5, 8.5, GOLD_DARK)
    c.ellipse(11.5, 14.5, 7.5, 7.5, GOLD)
    for x, y in ((7, 10), (8, 9), (9, 9), (6, 11), (6, 12)):
        c.px(x, y, GOLD_LIGHT)
    SIGNS[category](c)
    c.outline()
    return c


def _economy(c: Canvas) -> None:
    """A sheaf of rice."""
    for x in (9, 11, 13):
        c.vline(x + (0 if x == 11 else 0), 12, 19, INK)
    for x, y in ((8, 11), (10, 10), (12, 10), (14, 11), (11, 9)):
        c.px(x, y, INK)
    c.hline(9, 13, 16, P["red_dark"])


def _military(c: Canvas) -> None:
    """Crossed swords."""
    for i in range(8):
        c.px(7 + i, 11 + i, INK)
        c.px(15 - i, 11 + i, INK)
    c.hline(7, 9, 16, INK)
    c.hline(13, 15, 16, INK)


def _diplomacy(c: Canvas) -> None:
    """A rolled treaty with a red seal."""
    c.rect(8, 11, 7, 7, hex_color("f3e8cc"))
    c.vline(7, 10, 18, INK)
    c.vline(15, 10, 18, INK)
    c.rect(10, 13, 3, 3, P["red"])


def _officers(c: Canvas) -> None:
    """A helmet with a plume."""
    c.rect(8, 13, 7, 4, INK)
    c.hline(7, 15, 17, INK)
    c.vline(11, 9, 12, P["red"])
    c.vline(12, 10, 12, P["red"])
    c.px(10, 14, GOLD_LIGHT)


def _adventure(c: Canvas) -> None:
    """A banner on a pole."""
    c.vline(8, 9, 20, INK)
    c.rect(9, 10, 6, 4, P["red"])
    c.px(14, 12, GOLD)
    c.hline(9, 13, 14, P["red_dark"])


def _conquest(c: Canvas) -> None:
    """A crown."""
    c.rect(7, 14, 9, 4, INK)
    for x in (7, 11, 15):
        c.vline(x, 11, 14, INK)
    for x in (9, 13):
        c.vline(x, 12, 14, INK)
    c.px(11, 16, P["red"])


def _secret(c: Canvas) -> None:
    """A question mark."""
    for x, y in ((9, 11), (10, 10), (11, 10), (12, 10), (13, 11), (13, 12), (12, 13), (11, 14), (11, 15)):
        c.px(x, y, INK)
    c.px(11, 17, INK)
    c.px(11, 18, INK)


SIGNS = {"economy": _economy, "military": _military, "diplomacy": _diplomacy, "officers": _officers,
         "adventure": _adventure, "conquest": _conquest, "secret": _secret}


def draw_all() -> None:
    for category in RIBBONS:
        medal(category).save(f"icons/achievement_{category}.png", UI_SCALE)


if __name__ == "__main__":
    draw_all()
