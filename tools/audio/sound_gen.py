"""Generates every sound of the game (GDD §13, M14a): short 8-bit effects in assets/audio/sfx/ and
chiptune music on an East Asian pentatonic scale in assets/audio/music/. WAV, 22050 Hz, 16-bit mono.

Run: python tools/audio/sound_gen.py, then re-import in Godot. A file with the same name in
assets/audio/custom/ (.wav or .ogg) replaces the generated one in the game.
"""
from pathlib import Path
import wave

import numpy as np
from scipy.signal import lfilter

RATE = 22050
ROOT = Path(__file__).resolve().parents[2]
SFX_DIR = ROOT / "assets" / "audio" / "sfx"
MUSIC_DIR = ROOT / "assets" / "audio" / "music"
rng = np.random.default_rng(13)


# --- Building blocks ---------------------------------------------------------------------------

def t_axis(seconds: float) -> np.ndarray:
    return np.arange(int(seconds * RATE)) / RATE


def freq(note: int) -> float:
    """MIDI note number -> Hz."""
    return 440.0 * 2 ** ((note - 69) / 12)


def osc(kind: str, f, seconds: float, duty: float = 0.5) -> np.ndarray:
    """f is a number or an array of Hz (a sweep)."""
    t = t_axis(seconds)
    f = np.broadcast_to(np.asarray(f, dtype=float), t.shape)
    phase = np.cumsum(f) / RATE % 1.0
    if kind == "square":
        return np.where(phase < duty, 1.0, -1.0)
    if kind == "triangle":
        return 4.0 * np.abs(phase - 0.5) - 1.0
    if kind == "saw":
        return 2.0 * phase - 1.0
    return np.sin(2 * np.pi * phase)


def noise(seconds: float, steps: int = 1) -> np.ndarray:
    """White noise; steps > 1 holds each value (lower, crunchier 8-bit noise)."""
    n = int(seconds * RATE)
    values = rng.uniform(-1, 1, n // steps + 1)
    return np.repeat(values, steps)[:n]


def env(n: int, attack: float = 0.005, decay: float = 0.1, sustain: float = 0.0, release: float = 0.05) -> np.ndarray:
    """ADSR over n samples (sustain holds until the release)."""
    a, d, r = int(attack * RATE), int(decay * RATE), int(release * RATE)
    s = max(0, n - a - d - r)
    shape = np.concatenate([np.linspace(0, 1, max(a, 1)), np.linspace(1, sustain, max(d, 1)),
                            np.full(s, sustain), np.linspace(sustain, 0, max(r, 1))])
    if shape.size < n:
        shape = np.pad(shape, (0, n - shape.size))
    return shape[:n]


def expdecay(n: int, rate: float) -> np.ndarray:
    return np.exp(-np.arange(n) / RATE * rate)


def lowpass(x: np.ndarray, amount: float) -> np.ndarray:
    """One-pole low-pass, amount 0..1 (higher = darker)."""
    k = 1.0 - amount
    return lfilter([k], [1.0, -(1.0 - k)], x)


def highpass(x: np.ndarray, amount: float) -> np.ndarray:
    """What the low-pass takes away: only the bright part (amount 0..1, higher = more kept)."""
    return x - lowpass(x, amount)


def sword_clash(base: float, seed: int) -> np.ndarray:
    """Blade on blade: a sharp bright click, a short high ring with a shimmer (two close partials
    beating), a quick scrape of steel and a little thump of the blow."""
    local = np.random.default_rng(seed)
    sec = 0.35
    n = int(sec * RATE)
    click = highpass(local.uniform(-1, 1, int(0.012 * RATE)), 0.9) * expdecay(int(0.012 * RATE), 250)
    ring = np.zeros(n)
    for ratio, gain, rate in ((1.0, 1.0, 14), (1.013, 0.8, 14), (1.52, 0.55, 20), (2.27, 0.4, 28), (3.11, 0.25, 36)):
        f = base * ratio * (1 + local.uniform(-0.01, 0.01))
        ring += osc("sine", f, sec) * expdecay(n, rate) * gain
    scrape_n = int(0.09 * RATE)
    scrape = highpass(local.uniform(-1, 1, scrape_n), 0.85) * env(scrape_n, 0.004, 0.085, 0, 0.001)
    thump = drum(0.08, 220, 110, 45)
    return mix((click, 0, 0.9), (ring, 0.002, 0.55), (scrape, 0.004, 0.35), (thump, 0, 0.25))


def mix(*parts: tuple) -> np.ndarray:
    """parts: (signal, start_seconds, gain)."""
    end = max(int(start * RATE) + sig.size for sig, start, _ in parts)
    out = np.zeros(end)
    for sig, start, gain in parts:
        i = int(start * RATE)
        out[i:i + sig.size] += sig * gain
    return out


def save(path: Path, x: np.ndarray, peak: float = 0.85) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    top = np.max(np.abs(x)) or 1.0
    data = (x / top * peak * 32767).astype("<i2")
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(data.tobytes())


# --- Effects -----------------------------------------------------------------------------------

def tone(kind: str, note: float, seconds: float, decay_rate: float = 12.0, duty: float = 0.5) -> np.ndarray:
    x = osc(kind, freq(note), seconds, duty)
    return x * expdecay(x.size, decay_rate) * env(x.size, 0.002, seconds, 1.0, 0.01)


def drum(seconds: float = 0.5, start_hz: float = 150, end_hz: float = 50, rate: float = 7.0) -> np.ndarray:
    """A taiko-like drum: a falling sine with a soft noise hit."""
    f = np.geomspace(start_hz, end_hz, int(seconds * RATE))
    body = osc("sine", f, seconds) * expdecay(f.size, rate)
    hit = lowpass(noise(0.05), 0.6) * expdecay(int(0.05 * RATE), 60)
    return mix((body, 0, 1.0), (hit, 0, 0.5))


def metal(seconds: float, base: float, rate: float) -> np.ndarray:
    """A metallic ring: inharmonic partials over a noise burst."""
    parts = [osc("sine", base * r, seconds) * expdecay(int(seconds * RATE), rate * (1 + i * 0.4))
             for i, r in enumerate((1.0, 2.76, 5.4, 8.9))]
    ring = sum(p * g for p, g in zip(parts, (1.0, 0.6, 0.35, 0.2)))
    burst = noise(0.03) * expdecay(int(0.03 * RATE), 90)
    return mix((ring, 0, 1.0), (burst, 0, 0.8))


def effects() -> dict:
    s: dict = {}
    # UI
    s["click"] = tone("square", 84, 0.05, 60, 0.25)
    s["open"] = mix((tone("square", 79, 0.06, 40, 0.25), 0, 1), (tone("square", 86, 0.08, 30, 0.25), 0.05, 1))
    s["error"] = mix((tone("square", 52, 0.09, 15), 0, 1), (tone("square", 47, 0.14, 12), 0.09, 1))
    # The kingdom map
    thud = lowpass(noise(0.18, 3), 0.85) * expdecay(int(0.18 * RATE), 22)
    s["place_land"] = mix((thud, 0, 1.0), (drum(0.2, 110, 60, 20), 0, 0.8), (tone("triangle", 72, 0.1, 25), 0.02, 0.25))
    s["build"] = mix((drum(0.25, 160, 70, 18), 0, 1.0), (metal(0.25, 900, 20), 0.0, 0.4),
                     (drum(0.25, 160, 70, 18), 0.18, 0.8), (metal(0.25, 950, 20), 0.18, 0.35))
    s["complete"] = mix(*[(tone("square", n, 0.25, 8, 0.25), i * 0.08, 1.0) for i, n in enumerate((72, 76, 79, 84))])
    s["upgrade"] = mix(*[(tone("square", n, 0.3, 7, 0.5), i * 0.07, 0.8) for i, n in enumerate((67, 72, 74, 79, 84))],
                       (metal(0.8, 1400, 5), 0.35, 0.3))
    s["recruit"] = mix((drum(0.4), 0, 1.0), (drum(0.4), 0.16, 0.8), (tone("square", 62, 0.25, 6, 0.3), 0.3, 0.5),
                       (tone("square", 69, 0.35, 5, 0.3), 0.42, 0.5))
    s["demolish"] = mix((lowpass(noise(0.6, 4), 0.8) * expdecay(int(0.6 * RATE), 6), 0, 1.0), (drum(0.5, 90, 40, 6), 0, 0.9))
    gong_t = 2.2
    s["end_turn"] = mix((metal(gong_t, 180, 1.6), 0, 1.0), (osc("sine", 90, gong_t) * expdecay(int(gong_t * RATE), 1.5), 0, 0.6))
    s["coins"] = mix(*[(metal(0.25, 2400 + 300 * i, 18), i * 0.07, 0.6) for i in range(3)])
    s["event"] = mix(*[(tone("triangle", n, 0.4, 5), i * 0.12, 1.0) for i, n in enumerate((69, 74, 76, 81))])
    s["forge"] = mix((metal(0.6, 1100, 7), 0, 1.0), (metal(0.6, 1150, 7), 0.3, 0.8))
    s["level_up"] = mix(*[(tone("square", n, 0.18, 10, 0.25), i * 0.06, 0.8) for i, n in enumerate((76, 79, 84, 88))])
    # Ambience on the map (quiet; played now and then while the map effects are on)
    for i, (start, end) in enumerate(((2600, 3800), (3400, 2500))):
        chirps = [(osc("sine", np.linspace(start, end, int(0.07 * RATE)), 0.07) * env(int(0.07 * RATE), 0.01, 0.05, 0.3, 0.01), k * 0.11, 1.0)
                  for k in range(2 + i)]
        s[f"bird_{i + 1}"] = mix(*chirps)
    s["hammer"] = mix((metal(0.15, 1700, 30), 0, 1.0), (metal(0.15, 1650, 30), 0.35, 0.8))
    # Battle
    s["battle_start"] = mix(*[(drum(0.6, 130, 45, 5), t, g) for t, g in ((0, 1.0), (0.28, 0.7), (0.56, 1.0), (0.84, 0.7), (1.0, 1.0))])
    whoosh = lambda sec, rate: lowpass(noise(sec), 0.3) * env(int(sec * RATE), sec * 0.3, sec * 0.7, 0, 0.01) * rate
    s["bow"] = mix((osc("triangle", np.geomspace(300, 120, int(0.08 * RATE)), 0.08) * expdecay(int(0.08 * RATE), 30), 0, 1.0),
                   (whoosh(0.35, 1.0), 0.03, 0.5))
    s["crossbow"] = mix((metal(0.08, 600, 40), 0, 0.8), (drum(0.1, 200, 90, 40), 0, 0.8), (whoosh(0.25, 1.0), 0.02, 0.5))
    crack = noise(0.25, 2) * expdecay(int(0.25 * RATE), 25)
    s["gun"] = mix((crack, 0, 1.0), (drum(0.2, 120, 50, 18), 0, 0.6))
    boom = lowpass(noise(1.2, 6), 0.9) * expdecay(int(1.2 * RATE), 3.5)
    s["cannon"] = mix((boom, 0, 1.0), (drum(0.9, 80, 30, 4), 0, 1.0), (noise(0.05) * expdecay(int(0.05 * RATE), 50), 0, 0.5))
    hooves = [(lowpass(noise(0.06, 2), 0.7) * expdecay(int(0.06 * RATE), 50), k * 0.09 + (0.03 if k % 2 else 0), 1.0) for k in range(14)]
    s["charge"] = mix(*hooves, (lowpass(noise(1.4, 8), 0.95) * env(int(1.4 * RATE), 0.3, 1.0, 0, 0.1), 0, 0.6))
    for i, base in enumerate((2300, 2650, 3050)):
        s[f"clash_{i + 1}"] = sword_clash(base, 40 + i)
    horn_t = 1.1
    horn = osc("saw", 220 * (1 + 0.01 * np.sin(2 * np.pi * 5 * t_axis(horn_t))), horn_t)
    s["horn"] = lowpass(horn, 0.75) * env(horn.size, 0.1, 0.2, 0.7, 0.3)
    s["general_fallen"] = mix((drum(0.8, 100, 35, 4), 0, 1.0),
                              *[(tone("square", n, 0.3, 6, 0.5), 0.1 + i * 0.15, 0.4) for i, n in enumerate((64, 61, 57))])
    s["stratagem"] = mix((osc("sine", np.geomspace(400, 1600, int(0.5 * RATE)), 0.5) * env(int(0.5 * RATE), 0.05, 0.45, 0, 0.01), 0, 0.6),
                         *[(tone("triangle", n, 0.3, 8), 0.3 + i * 0.05, 0.4) for i, n in enumerate((81, 86, 88, 93))])
    return s


# --- Music -------------------------------------------------------------------------------------
# Pentatonic (gong, shang, jue, zhi, yu) on D: D E F# A B.
SCALE = [0, 2, 4, 7, 9]
MINOR_SCALE = [0, 3, 5, 7, 10]


def degree(scale: list, root: int, d: int) -> int:
    return root + 12 * (d // len(scale)) + scale[d % len(scale)]


def render_notes(notes: list, beat: float, kind: str, duty: float, total: float, gain: float, decay: float = 4.0,
                 vibrato: float = 0.0) -> np.ndarray:
    """notes: (beat_start, beats, midi or None)."""
    out = np.zeros(int(total * RATE) + RATE)
    for start, length, note in notes:
        if note is None:
            continue
        sec = length * beat
        f = freq(note)
        if vibrato:
            f = f * (1 + vibrato * np.sin(2 * np.pi * 5.5 * t_axis(sec)))
        x = osc(kind, f, sec, duty)
        x *= env(x.size, 0.005, sec * 0.9, 0.35, min(0.05, sec * 0.1)) * expdecay(x.size, decay)
        i = int(start * beat * RATE)
        out[i:i + x.size] += x * gain
    return out[:int(total * RATE)]


def percussion(pattern: list, beat: float, total: float, gain: float) -> np.ndarray:
    """pattern: (beat_start, 'k' | 's' | 'h')."""
    out = np.zeros(int(total * RATE) + RATE)
    hits = {"k": drum(0.3, 120, 45, 10), "s": lowpass(noise(0.12, 2), 0.3) * expdecay(int(0.12 * RATE), 30),
            "h": lowpass(noise(0.03), 0.5) * expdecay(int(0.03 * RATE), 140), "g": lowpass(metal(1.2, 220, 2.5), 0.6)}
    for start, kind in pattern:
        x = hits[kind]
        i = int(start * beat * RATE)
        out[i:i + x.size] += x * (0.25 if kind == "h" else 1.0)
    return out[:int(total * RATE)] * gain


def melody_phrase(local: np.random.Generator, bars: int, scale: list, root: int, low: int, high: int,
                  rhythm: list) -> list:
    """A walking melody: steps of the scale, mostly small, ending on the root."""
    notes = []
    d = (low + high) // 2
    t = 0.0
    for bar in range(bars):
        for length in rhythm[bar % len(rhythm)]:
            if local.random() < 0.12 and t > 0:
                notes.append((t, length, None))
            else:
                d = int(np.clip(d + local.choice([-2, -1, -1, 0, 1, 1, 2]), low, high))
                notes.append((t, length, degree(scale, root, d)))
            t += length
    # Land on the root at the end of the phrase.
    last_t, last_len, _ = notes[-1]
    notes[-1] = (last_t, last_len, degree(scale, root, (low + high) // 2 // 5 * 5))
    return notes


def song(name: str, bpm: float, bars: int, scale: list, root: int, rhythms: list, bass_pattern: list,
         drums: str, seed: int, lead: str = "square", lead_duty: float = 0.25, lead_gain: float = 0.32) -> np.ndarray:
    local = np.random.default_rng(seed)
    beat = 60.0 / bpm
    total = bars * 4 * beat
    # Two phrases (A, B) of a quarter of the song each: A A B A.
    quarter = bars // 4
    a = melody_phrase(local, quarter, scale, root, 5, 10, rhythms)
    b = melody_phrase(local, quarter, scale, root, 7, 12, rhythms[::-1])
    lead_notes = []
    for i, phrase in enumerate((a, a, b, a)):
        lead_notes += [(t + i * quarter * 4, l, n) for t, l, n in phrase]
    lead_track = lowpass(render_notes(lead_notes, beat, lead, lead_duty, total, lead_gain, 2.0, vibrato=0.004), 0.7)
    # Harmony: the lead a scale step lower, softer, on the B phrase only.
    harmony = [(t, l, None if n is None else n - 5) for t, l, n in lead_notes if quarter * 8 <= t < quarter * 12]
    harmony_track = lowpass(render_notes(harmony, beat, "triangle", 0.5, total, 0.14, 3.0), 0.5)
    bass_notes = []
    for bar in range(bars):
        chord = bass_pattern[bar % len(bass_pattern)]
        for k in range(4):
            bass_notes.append((bar * 4 + k, 1, degree(scale, root - 24, chord + (0 if k % 2 == 0 else 3))))
    bass_track = render_notes(bass_notes, beat, "triangle", 0.5, total, 0.45, 3.0)
    pattern = []
    for bar in range(bars):
        base = bar * 4
        if drums == "calm":
            pattern += [(base, "k"), (base + 2.5, "k")] + [(base + h, "h") for h in (1, 3)]
            if bar % 8 == 0:
                pattern.append((base, "g"))
        elif drums == "war":
            pattern += [(base + k, "k") for k in (0, 0.75, 1.5, 2, 2.75, 3.5)] + [(base + s, "s") for s in (1, 3)]
            pattern += [(base + h / 2, "h") for h in range(8)]
            if bar % 4 == 0:
                pattern.append((base, "g"))
        else:
            pattern += [(base, "k")] + ([(base, "g")] if bar % 4 == 0 else [])
    drum_track = percussion(pattern, beat, total, 0.35 if drums != "war" else 0.45)
    out = lowpass(lead_track + harmony_track + bass_track + drum_track, 0.35)
    # A tiny fade at both ends so the loop point never clicks.
    fade = int(0.01 * RATE)
    out[:fade] *= np.linspace(0, 1, fade)
    out[-fade:] *= np.linspace(1, 0, fade)
    return out


def sting(notes: list, bpm: float, scale_gain: float, drums: list, kind: str = "square") -> np.ndarray:
    beat = 60.0 / bpm
    total = max(t + l for t, l, _ in notes) * beat + 1.5
    lead = lowpass(render_notes(notes, beat, kind, 0.5, total, 0.35, 1.5, vibrato=0.006), 0.7)
    low = render_notes([(t, l, n - 12) for t, l, n in notes], beat, "triangle", 0.5, total, 0.3, 1.5)
    return lead + low + percussion(drums, beat, total, scale_gain)


def music() -> dict:
    m: dict = {}
    calm = [[1, 1, 2], [0.5, 0.5, 1, 2], [2, 1, 1], [1, 0.5, 0.5, 2]]
    m["menu"] = song("menu", 84, 16, SCALE, 74, calm, [0, 3, 4, 0], "calm", 3, "triangle", 0.5, 0.42)
    m["kingdom"] = song("kingdom", 96, 32, SCALE, 74, calm + [[1, 1, 1, 1]], [0, 0, 3, 4, 0, 3, 1, 0], "calm", 8)
    war = [[0.5, 0.5, 0.5, 0.5, 1, 1], [1, 0.5, 0.5, 1, 1], [0.5, 0.5, 1, 2], [0.25, 0.25, 0.5, 1, 1, 1]]
    m["battle"] = song("battle", 138, 32, MINOR_SCALE, 69, war, [0, 0, 3, 4, 0, 4, 3, 0], "war", 21, "square", 0.5, 0.3)
    march = [[0.5, 0.5, 1, 1, 1], [1, 0.5, 0.5, 2], [0.5, 0.5, 0.5, 0.5, 2], [1, 1, 0.5, 0.5, 1]]
    m["expedition"] = song("expedition", 126, 32, SCALE, 72, march, [0, 4, 3, 4, 0, 3, 4, 0], "war", 34, "square", 0.25,
                           0.3)
    m["victory"] = sting([(0, 0.5, 74), (0.5, 0.5, 78), (1, 0.5, 81), (1.5, 1.5, 86), (3, 0.5, 83), (3.5, 2.5, 86)], 120, 0.5,
                         [(0, "k"), (1, "k"), (1.5, "g"), (3.5, "g")])
    m["defeat"] = sting([(0, 1, 69), (1, 1, 67), (2, 1, 65), (3, 3, 62)], 70, 0.5, [(0, "g"), (3, "k")], "triangle")
    return m


def main() -> None:
    for name, x in effects().items():
        save(SFX_DIR / f"{name}.wav", x)
    for name, x in music().items():
        save(MUSIC_DIR / f"{name}.wav", x, 0.6)
    print("sounds written to", SFX_DIR.parent)


if __name__ == "__main__":
    main()
