# Generates kaiju/ghidorah/textures/ghidorah.png, the 256x256 atlas used by tools/ghidorah_model.py.
# Tile constants and RECTS must match the ones there.
#   python3 tools/ghidorah_texture.py kaiju/ghidorah/textures/ghidorah.png
# Alpha tiles (membranes, crescent, tail fan) are fully transparent outside their outline;
# Luanti clips fully transparent pixels on entity meshes (same trick as mothra's wings).
import math, random, sys
from PIL import Image

rng = random.Random(23)  # deterministic output
BASE, HILITE, SHADOW, CREVICE = (212, 166, 42), (242, 209, 107), (140, 106, 20), (90, 65, 8)
# belly and membranes are paler than the scales, so body and wings read apart from afar
BELLY_C, MEMBRANE_C, VEIN, EYE_C = (222, 190, 112), (240, 212, 128), (166, 124, 30), (214, 40, 40)
IVORY_C, MOUTH_C = (244, 238, 220), (122, 30, 30)

# transparent filler in the membrane colour, so filtering at alpha edges doesn't bleed dark
img = Image.new("RGBA", (256, 256), MEMBRANE_C + (0,))
px = img.load()

(SCALES, SCALES_DARK, BELLY, CROWN, MEMBRANE, MEMBRANE_ARM, CRESCENT, FAN, EYE, MOUTH,
 IVORY, CLAW, BLACK) = range(13)
RECTS = {SCALES: (0, 0, 64, 64), SCALES_DARK: (64, 0, 64, 64), BELLY: (128, 0, 64, 64),
         CROWN: (192, 0, 64, 64),
         MEMBRANE: (0, 64, 96, 64), MEMBRANE_ARM: (96, 64, 64, 64),
         CRESCENT: (160, 64, 64, 32), FAN: (160, 96, 64, 32),
         EYE: (224, 64, 32, 32), MOUTH: (224, 96, 32, 32),
         IVORY: (0, 128, 64, 64), CLAW: (64, 128, 64, 64), BLACK: (128, 128, 32, 32)}

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

def scales(base, hi, lo, crev):
    # overlapping rows of 8x6 scales, every other row offset by half a scale: lit at the
    # top of each scale, shadowed at its lower rim, a dark crevice where the next row starts
    def fn(x, y):
        row = y // 6
        sx = (x + (4 if row % 2 else 0)) % 8
        sy = y % 6
        # rounded lower rim: the corners of a scale belong to the crevice
        rim = sy == 5 or (sy == 4 and sx in (0, 7)) or sx == 0 and sy >= 2
        if rim:
            return shade(crev, rng.randint(-6, 6))
        if sy == 0 or (sy == 1 and 2 <= sx <= 5):
            return shade(hi, rng.randint(-10, 6))
        if sy == 4 or sx == 7:
            return shade(lo, rng.randint(-8, 8))
        return shade(base, rng.randint(-9, 9))
    return fn

tile(SCALES, scales(BASE, HILITE, SHADOW, mix(SHADOW, CREVICE, 0.45)))
tile(SCALES_DARK, scales(mix(BASE, SHADOW, 0.55), mix(BASE, HILITE, 0.2), mix(SHADOW, CREVICE, 0.5), CREVICE))
# belly: horizontal ribs, lit on top, crevice between them
tile(BELLY, lambda x, y: shade(CREVICE if y % 8 == 7 else HILITE if y % 8 == 0 else
                               mix(BELLY_C, SHADOW, (y % 8) / 14), rng.randint(-6, 6) - (10 if x % 16 == 0 else 0)))
# crown / horn gold: brighter, polished, with fine vertical grooves
tile(CROWN, lambda x, y: shade(mix(HILITE, BASE, y / 90), rng.randint(-6, 6) - (28 if x % 5 == 0 else 0)))

def membrane(x, y):
    # 96x64 sector: the finger runs along the top edge (x = wrist -> tip); the membrane fills
    # the wedge below it down to the next finger, which crosses the bottom edge at x ~ 80.
    # The outer (trailing) edge between the two fingertips is a concave scallop.
    edge = 95 - 15 * (y / 63) - 13 * math.sin(math.pi * y / 63)
    if x > edge:
        return None
    if y < 3:
        return shade(SHADOW, rng.randint(-6, 6))            # the finger bone itself
    if x > edge - 2.5:
        return shade(CREVICE, 10)                            # dark rim along the scallop
    ang = math.atan2(y, x + 4)
    r = math.hypot(x + 4, y)
    if abs((ang * 4) % 1.0 - 0.5) / 4 * r < 0.7:             # veins fanning out from the wrist
        return shade(VEIN, rng.randint(-6, 6))
    if int(r) % 22 == 0:                                     # faint cross veins
        return mix(MEMBRANE_C, VEIN, 0.5)
    return shade(mix(MEMBRANE_C, BASE, y / 220), rng.randint(-7, 7) - int(x / 8))

def membrane_arm(x, y):
    # 64x64 panel hanging behind an arm bone (top edge); two scallops on the trailing edge
    edge = 62 - 12 * abs(math.sin(math.pi * x / 32 + math.pi / 2)) ** 0.7
    if y > edge:
        return None
    if y > edge - 2.5:
        return shade(CREVICE, 10)
    if x % 16 in (0, 1) or (y % 20 == 10 and x % 16 < 9):
        return shade(VEIN, rng.randint(-6, 6))
    return shade(mix(MEMBRANE_C, BASE, 0.25), rng.randint(-7, 7) - y // 6)

def crescent(x, y):
    # 64x32 crescent, horns up: outer ellipse minus an inner one shifted upwards
    dx = (x - 31.5) / 31.5
    outer = dx * dx + ((y - 4) / 27.0) ** 2
    inner = (dx / 0.72) ** 2 + ((y + 4) / 24.0) ** 2
    if outer > 1 or inner < 1 or y < 1:
        return None
    return shade(HILITE if outer < 0.8 else SHADOW, rng.randint(-8, 8) - (20 if x % 6 == 0 else 0))

def fan(x, y):
    # 64x32 tail fan: x = base -> tips, five spikes spreading out, gaps transparent
    d = abs(y - 15.5)
    spoke = min(abs(d - k * (x / 63) * 13) for k in (0, 0.5, 1))
    width = 3.6 * (1 - x / 72)
    if x > 14 and spoke > width:
        return None
    if x <= 14 and d > 4 + x * 0.5:
        return None
    return shade(SHADOW if x > 14 and spoke > width - 1 else mix(BASE, IVORY_C, x / 70), rng.randint(-8, 8))

def eye(x, y):
    # coarse 8x8 design (4px cells) so it survives minification: dark rim, red glow, slit
    cx, cy = x // 4, y // 4
    if cx in (0, 7) or cy in (0, 7):
        return (40, 10, 8)
    if cx in (3, 4) and 2 <= cy <= 5:
        return (20, 4, 4)
    return shade(EYE_C, 30 - int(max(abs(cx - 3.5), abs(cy - 3.5)) * 14))

tile(MEMBRANE, membrane)
tile(MEMBRANE_ARM, membrane_arm)
tile(CRESCENT, crescent)
tile(FAN, fan)
tile(EYE, eye)
tile(MOUTH, lambda x, y: shade(MOUTH_C, rng.randint(-12, 12)))
tile(IVORY, lambda x, y: shade(IVORY_C, rng.randint(-6, 6) - y // 4 - (14 if x % 7 == 0 else 0)))
tile(CLAW, lambda x, y: shade((226, 214, 180), rng.randint(-6, 6) - y // 3))
tile(BLACK, lambda x, y: (16, 12, 6))

img.save(sys.argv[1])
print("WROTE", sys.argv[1])
