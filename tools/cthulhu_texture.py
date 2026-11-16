# Generates kaiju/cthulhu/textures/cthulhu.png, the 256x256 atlas used by tools/cthulhu_model.py.
# Tile constants and RECTS must match the ones there.
#   python3 tools/cthulhu_texture.py kaiju/cthulhu/textures/cthulhu.png
# Palette: wet sea-green to green-black scales with slime highlights and rare gold flecks
# (the idol's "greenish-black stone with golden flecks"), nothing white, no pink or purple.
# The wing membrane is an alpha tile, fully transparent outside its outline; Luanti clips
# fully transparent pixels on entity meshes (same trick as mothra's and ghidorah's wings).
import math, random, sys
from PIL import Image

rng = random.Random(23)  # deterministic output
SKIN_C, SKIN_DARK_C, BELLY_C, FEELER_C = (46, 82, 66), (22, 38, 34), (96, 118, 82), (62, 104, 80)
SLIME, GOLD, WING_C, SOCKET_C = (128, 178, 124), (196, 160, 72), (34, 56, 48), (14, 22, 18)
HORN, HORN_TIP, IRIS, PUPIL = (30, 30, 26), (150, 140, 110), (214, 222, 120), (10, 12, 10)

# transparent filler in the membrane colour, so filtering at alpha edges doesn't bleed light
img = Image.new("RGBA", (256, 256), WING_C + (0,))
px = img.load()

(SKIN, SKIN_DARK, BELLY, FEELER, WING, CLAW, EYE, SOCKET, CLAW_TIP) = range(9)
RECTS = {SKIN: (0, 0, 64, 64), SKIN_DARK: (64, 0, 64, 64), BELLY: (128, 0, 64, 64),
         FEELER: (192, 0, 64, 64), WING: (0, 64, 128, 32), CLAW: (128, 64, 64, 64),
         EYE: (192, 64, 32, 32), SOCKET: (224, 64, 32, 32), CLAW_TIP: (192, 96, 32, 32)}

def clamp(c):
    return tuple(max(0, min(255, int(v))) for v in c)

def shade(c, d):
    return clamp(v + d for v in c)

def mix(a, b, t):
    return clamp(x + (y - x) * t for x, y in zip(a, b))

def tile(index, fn):
    ox, oy, w, h = RECTS[index]
    for y in range(h):
        for x in range(w):
            c = fn(x, y)
            if c is not None:
                px[ox + x, oy + y] = clamp(c) + (255,)

# a coarse mottle (8 px blobs) shared by the skin tiles, so the hide looks blotchy and wet
MOTTLE = [[rng.randint(-7, 7) for _ in range(9)] for _ in range(9)]
def mottle(x, y):
    return MOTTLE[y // 8][x // 8]

def streak(x, y, seed):
    # sparse short vertical slime runs: wet highlights
    r = random.Random(seed * 1000 + x)
    start, length = r.randint(0, 63), r.randint(3, 7)
    return r.random() < 0.18 and start <= y < start + length

def scales(base, slime_mix, gold_rate, seed):
    # Overlapping fish scales, 8x6 px, every other row offset by half a scale. Only the
    # rounded lower rim of each scale is a dark crevice (a U, never a straight line across
    # the tile, which made every box look like a stack of slats); the scale is lit just
    # under the rim above it and darkens towards its own rim.
    hi, lo, crev = mix(base, SLIME, 0.22), shade(base, -9), mix(base, (0, 0, 0), 0.42)
    RIM = (2, 4, 5, 5, 5, 5, 4, 2)          # rim row for each column of a scale
    gold = set()                             # rare gold striations, 2-3 px long
    g = random.Random(seed)
    for _ in range(int(gold_rate * 64 * 64 / 2.5)):
        gx, gy = g.randint(0, 63), g.randint(0, 63)
        for i in range(g.randint(2, 3)):
            gold.add(((gx + i) % 64, gy))
    def fn(x, y):
        row = y // 6
        sx = (x + (4 if row % 2 else 0)) % 8
        sy = y % 6
        m = mottle(x, y)
        if (x, y) in gold:
            return shade(mix(GOLD, base, 0.25), rng.randint(-14, 8))
        if sy == RIM[sx] or (sx in (0, 7) and sy == 3):
            return shade(crev, rng.randint(-2, 2))
        if streak(x, y, seed):
            return mix(base, SLIME, slime_mix + rng.random() * 0.15)
        # below the rim = the top of the scale underneath (lit); above it = this scale
        d = (sy - RIM[sx]) % 6               # rows below this column's rim
        if d == 1:
            return shade(hi, m + rng.randint(-3, 3))
        if d == 5:
            return shade(lo, m + rng.randint(-3, 3))
        return shade(base, m + rng.randint(-3, 3))
    return fn

tile(SKIN, scales(SKIN_C, 0.4, 0.006, 1))
tile(SKIN_DARK, scales(SKIN_DARK_C, 0.3, 0.004, 2))

def belly(x, y):
    # rubbery horizontal bands, lit on top, a dark crease between them, wet streaks
    band = y % 8
    if rng.random() < 0.006:
        return shade(GOLD, -10)
    if band == 7:
        return shade(mix(BELLY_C, SKIN_DARK_C, 0.7), rng.randint(-4, 4))
    if band == 0:
        return shade(mix(BELLY_C, SLIME, 0.4), rng.randint(-6, 6))
    if streak(x, y, 3):
        return mix(BELLY_C, SLIME, 0.5)
    return shade(mix(BELLY_C, SKIN_C, band / 14), mottle(x, y) // 2 + rng.randint(-6, 6))

def feeler(x, y):
    # smooth, slick, faint rings (no suckers), a darker underside blotch here and there
    if y % 7 == 6:
        return shade(FEELER_C, -18 + rng.randint(-4, 4))
    if streak(x, y, 4):
        return mix(FEELER_C, SLIME, 0.55)
    return shade(FEELER_C, mottle(x, y) + rng.randint(-6, 6))

def wing(x, y):
    # 128x32: x runs from the hook (0) down the blade (127); y = 0 is the rib, y = 31 the
    # free edge. A narrow blade: pointed at the top, full width in the middle, tapering
    # towards the bottom, with a ragged scalloped free edge.
    u = x / 127
    w = 31 * min(1.0, u / 0.16) * (1 - 0.45 * max(0, (u - 0.7) / 0.3))
    w -= 3.2 * abs(math.sin(math.pi * x / 18)) ** 0.6                  # scallops
    if y > w:
        return None
    if y < 2:
        return shade(SKIN_DARK_C, rng.randint(-4, 4))                     # along the rib
    if y > w - 1.6:
        return shade(SKIN_DARK_C, -6)                                     # dark ragged rim
    if abs(y - (3 + 0.45 * w)) < 0.9 or abs(y - (3 + 0.8 * w)) < 0.7:   # two thin ribs
        return shade(SKIN_DARK_C, 4 + rng.randint(-4, 4))
    return shade(mix(WING_C, SKIN_C, 0.25 + 0.2 * math.sin(x / 9)), rng.randint(-6, 6))

def claw(x, y):
    # dark horn with fine lengthwise grain and a few pale streaks
    if x % 9 == 0:
        return shade(HORN, -8)
    if rng.random() < 0.05:
        return mix(HORN, HORN_TIP, 0.5)
    return shade(HORN, rng.randint(-5, 5) + (6 if x % 9 == 4 else 0))

def claw_tip(x, y):
    return shade(mix(HORN_TIP, HORN, (y / 31) * 0.35), rng.randint(-8, 8))

def eye(x, y):
    # coarse 8x8 design (4 px cells) so it survives minification: a round, lidless, pale
    # sickly yellow-green eye (dark corners), with a W-shaped bar pupil (cuttlefish)
    cx, cy = x // 4, y // 4
    if (cx in (0, 7)) + (cy in (0, 7)) == 2 or (cy == 7 and cx in (1, 6)):
        return SOCKET_C
    if cx in (0, 7) or cy in (0, 7):
        return mix(IRIS, SOCKET_C, 0.55)
    if cy == 4 and 1 <= cx <= 6 or cy == 3 and cx in (1, 3, 4, 6):
        return PUPIL
    return shade(IRIS, 14 - int(max(abs(cx - 3.5), abs(cy - 3.5)) * 8))

tile(BELLY, belly)
tile(FEELER, feeler)
tile(WING, wing)
tile(CLAW, claw)
tile(CLAW_TIP, claw_tip)
tile(EYE, eye)
tile(SOCKET, lambda x, y: shade(SOCKET_C, rng.randint(-4, 4)))

img.save(sys.argv[1])
print("WROTE", sys.argv[1])
