"""Turns a big AI portrait into a game pool portrait (96x96, transparent, see
docs/portrait_ai_guide.md).

A Gemini image (1024x1024) first loses its faint white sparkle watermark: the watermark's
alpha, measured once on plain green backgrounds, is in gemini_sparkle.png and is blended out.
Fake pixel art (an image upscaled from a small sprite, often unevenly and as a JPEG) is first
brought back to its real pixels: the block size and offset are measured on each axis from the
edges, and every block takes the median color of its middle. The background is then removed:
a flat key color (the corners' color, e.g. the #00FF00 asked for in the prompt) or a baked-in
checkerboard. The figure is cropped, shrunk only if wider than 96 px, and placed 5 px below the
top (a short figure sits on the bottom edge); whatever does not fit is cut at the bottom. Hard alpha, at most 48 colors
(or the given count: small faces such as the counselors' lose their lips to a gray robe at 48).

    python tools/art/fix_portraits.py <source image> <output .png> [colors]
"""
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

SIZE, TOP, COLORS = 96, 5, 48
# Opaque islands smaller than this (in real pixels) are background sparkles, not the figure.
SPECK_PIXELS = 60
# Block sizes the grid search tries, in source pixels.
MIN_BLOCK, MAX_BLOCK, BLOCK_STEP = 3.0, 20.0, 0.05
# Gemini's watermark: its alpha mask and where its top-left corner sits in a 1024x1024 image.
GEMINI_SIZE, GEMINI_SPARKLE_AT = (1024, 1024), 864
GEMINI_SPARKLE = Path(__file__).with_name("gemini_sparkle.png")


def remove_gemini_sparkle(im: Image.Image) -> Image.Image:
    """Undoes the white watermark blend: shown = (1 - alpha) * color + alpha * white."""
    if im.size != GEMINI_SIZE:
        return im
    alpha = np.asarray(Image.open(GEMINI_SPARKLE), dtype=float)[..., None] / 255.0
    a = np.asarray(im).astype(float)
    at, size = GEMINI_SPARKLE_AT, alpha.shape[0]
    area = a[at:at + size, at:at + size, :3]
    a[at:at + size, at:at + size, :3] = np.clip((area - alpha * 255.0) / (1.0 - alpha), 0, 255)
    return Image.fromarray(a.round().astype(np.uint8))


def find_grid(gray: np.ndarray, axis: int) -> tuple[float, float]:
    """(block size, offset of the first block edge) along an axis, from the edge strength."""
    edges = np.abs(np.diff(gray, axis=axis)).sum(axis=1 - axis)
    edges = edges - edges.mean()
    positions = np.arange(len(edges)) + 0.5
    best = (0.0, 1.0, 0.0)
    for period in np.arange(MIN_BLOCK, MAX_BLOCK, BLOCK_STEP):
        wave = (edges * np.exp(2j * np.pi * positions / period)).sum()
        # Weight by sqrt(period): smaller divisors of the real block size fit almost as well.
        score = abs(wave) * period ** 0.5
        if score > best[0]:
            best = (score, period, (np.angle(wave) / (2 * np.pi) * period) % period)
    return best[1], best[2]


def to_real_pixels(im: Image.Image) -> Image.Image:
    rgb = np.asarray(im.convert("RGB"), dtype=float)
    gray = rgb.mean(axis=2)
    (px, ox), (py, oy) = find_grid(gray, 1), find_grid(gray, 0)
    if px < 2.0 and py < 2.0:
        return im.convert("RGBA")
    xs = np.arange(ox - px, im.width, px)
    ys = np.arange(oy - py, im.height, py)
    out = np.zeros((len(ys) - 1, len(xs) - 1, 3), dtype=np.uint8)
    for j in range(len(ys) - 1):
        y0, y1 = ys[j] + (ys[j + 1] - ys[j]) * 0.25, ys[j] + (ys[j + 1] - ys[j]) * 0.75
        for i in range(len(xs) - 1):
            x0, x1 = xs[i] + (xs[i + 1] - xs[i]) * 0.25, xs[i] + (xs[i + 1] - xs[i]) * 0.75
            cell = rgb[max(0, int(y0)):max(1, int(np.ceil(y1))), max(0, int(x0)):max(1, int(np.ceil(x1)))]
            if cell.size:
                out[j, i] = np.median(cell.reshape(-1, 3), axis=0)
    print("  grid %.2f x %.2f px -> %d x %d" % (px, py, out.shape[1], out.shape[0]))
    return Image.fromarray(out).convert("RGBA")


def remove_key_color(im: Image.Image, key: tuple, tolerance: float = 90.0) -> Image.Image:
    a = np.asarray(im).copy()
    diff = np.sqrt(((a[..., :3].astype(float) - np.array(key[:3], dtype=float)) ** 2).sum(axis=2))
    a[diff < tolerance, 3] = 0
    return Image.fromarray(a)


def is_checker(p) -> bool:
    r, g, b, a = p
    return a < 128 or (min(r, g, b) >= 226 and max(r, g, b) - min(r, g, b) <= 8)


def remove_checker(im: Image.Image) -> Image.Image:
    """Flood fill from the borders through near-white gray pixels (a painted checkerboard)."""
    w, h = im.size
    px = im.load()
    seen = bytearray(w * h)
    queue = deque((x, y) for x in range(w) for y in (0, h - 1))
    queue.extend((x, y) for y in range(h) for x in (0, w - 1))
    while queue:
        x, y = queue.popleft()
        if seen[y * w + x]:
            continue
        seen[y * w + x] = 1
        if not is_checker(px[x, y]):
            continue
        px[x, y] = (0, 0, 0, 0)
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx]:
                queue.append((nx, ny))
    return im


def corner_color(im: Image.Image) -> tuple:
    """The background color: the top edge and the upper half of the sides (a bust touches the
    bottom, so the bottom corners are clothes)."""
    a = np.asarray(im.convert("RGBA"))
    half = a.shape[0] // 2
    border = np.concatenate([a[:4].reshape(-1, 4), a[:half, :4].reshape(-1, 4), a[:half, -4:].reshape(-1, 4)])
    return tuple(int(v) for v in np.median(border, axis=0))


def remove_specks(im: Image.Image) -> Image.Image:
    """Clears opaque islands smaller than SPECK_PIXELS (sparkles Gemini scatters on the
    background); anything that large or touching the figure stays."""
    a = np.asarray(im).copy()
    solid = a[..., 3] >= 128
    h, w = solid.shape
    seen = np.zeros_like(solid)
    for y0, x0 in zip(*np.nonzero(solid)):
        if seen[y0, x0]:
            continue
        island, queue = [], deque([(y0, x0)])
        seen[y0, x0] = True
        while queue:
            y, x = queue.popleft()
            island.append((y, x))
            for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                if 0 <= ny < h and 0 <= nx < w and solid[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    queue.append((ny, nx))
        if len(island) < SPECK_PIXELS:
            for y, x in island:
                a[y, x, 3] = 0
    return Image.fromarray(a)


def fix(src: str, dst: str, colors: int = COLORS) -> None:
    im = remove_gemini_sparkle(Image.open(src).convert("RGBA"))
    key = corner_color(im)
    im = to_real_pixels(im)
    if key[3] >= 128:
        r, g, b = key[:3]
        flat_gray = min(r, g, b) >= 226 and max(r, g, b) - min(r, g, b) <= 8
        im = remove_checker(im) if flat_gray else remove_key_color(im, key)
    alpha = im.getchannel("A").point(lambda v: 255 if v >= 128 else 0)
    im.putalpha(alpha)
    im = remove_specks(im)
    im = im.crop(im.getbbox())
    if im.width > SIZE:
        im = im.resize((SIZE, max(1, round(im.height * SIZE / im.width))), Image.NEAREST)
    alpha = im.getchannel("A")
    rgb = Image.new("RGB", im.size)
    rgb.paste(im.convert("RGB"), mask=alpha)
    piece = rgb.quantize(colors, method=Image.Quantize.MEDIANCUT).convert("RGBA")
    piece.putalpha(alpha)
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    # 5 px below the top, cut at the bottom; a short figure sits on the bottom edge instead.
    out.paste(piece, ((SIZE - im.width) // 2, max(TOP, SIZE - im.height)), piece)
    out.save(dst)


if __name__ == "__main__":
    fix(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else COLORS)
