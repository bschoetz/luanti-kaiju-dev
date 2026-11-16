# Generates kaiju/mothra/textures/mothra.png, the 256x256 atlas used by tools/mothra_model.py.
# Tile constants and RECTS must match the ones there.
#   python3 tools/mothra_texture.py kaiju/mothra/textures/mothra.png
# Wing tiles: x = root -> tip, y = leading edge -> trailing edge; transparent outside the
# wing outline (Luanti clips fully transparent pixels on entity meshes).
import math, random, sys
from PIL import Image

T = 64
rng = random.Random(11)
img = Image.new("RGBA", (4 * T, 4 * T), (0, 0, 0, 0))
px = img.load()

(FOREWING, HINDWING, FUR_BROWN, FUR_WHITE, ABD_TAN, ABD_CREAM, EYE, ANTENNA,
 LEG, FUR_ORANGE) = range(10)
# Atlas rectangles (x, y, w, h). The wing rectangles have the aspect of the wing plates
# so their texels come out square.
RECTS = {FOREWING: (0, 0, 128, 64), HINDWING: (128, 0, 96, 64),
         FUR_BROWN: (0, 64, 64, 64), FUR_WHITE: (64, 64, 64, 64),
         ABD_TAN: (128, 64, 64, 64), ABD_CREAM: (192, 64, 64, 64),
         EYE: (0, 128, 64, 64), ANTENNA: (64, 128, 64, 64),
         LEG: (128, 128, 64, 64), FUR_ORANGE: (192, 128, 64, 64)}

ORANGE, YELLOW, BLACK, WHITE = (232, 129, 26), (247, 197, 49), (30, 22, 18), (244, 239, 226)
RED, BLUE, BROWN = (200, 50, 30), (58, 143, 216), (138, 90, 46)

def clamp(c):
    return tuple(max(0, min(255, int(v))) for v in c)

def shade(c, d):
    return clamp(v + d for v in c)

def tile(index, fn):
    ox, oy, w, h = RECTS[index]
    for y in range(h):
        for x in range(w):
            c = fn(x, y)
            if c is not None:
                px[ox + x, oy + y] = clamp(c) + (255,)

def eyespot(x, y, cx, cy, r):
    d = math.hypot(x - cx, y - cy)
    if d > r:
        return None
    if math.hypot(x - cx + r * 0.25, y - cy + r * 0.25) < r * 0.12:
        return WHITE                       # highlight
    for frac, col in ((0.3, RED), (0.48, WHITE), (0.72, YELLOW), (1.0, BLACK)):
        if d <= r * frac:
            return col
    return None

def wing(width, chord, spot, spot_r, base):
    def fn(x, y):
        c = chord(x)
        if y > c:
            return None                    # outside the outline
        # distance to the outline; the trailing edge is sampled sideways too, so the
        # border keeps its width where the outline runs steeply
        edge = min(y, min(chord(x + d) - y + abs(d) for d in range(-3, 4) if 0 <= x + d < width))
        if edge < 3 or x < 2:
            # pale 2x2 dots along the dark outer margin (not on the leading edge)
            if y >= 3 and x > 8 and (x // 2 + y // 2) % 4 == 0:
                return WHITE
            return BLACK
        e = eyespot(x, y, *spot, spot_r)
        if e:
            return e
        # veins fanning out from the root, about one pixel wide at any radius
        ang = math.atan2(y - 8, x + 6)
        if x > 6 and abs((ang * 4.5) % 1.0 - 0.5) / 4.5 * math.hypot(x + 6, y - 8) < 0.6:
            return shade(BLACK, 20)
        col = base(x, y, c)
        return shade(col, rng.randint(-6, 6))
    return fn

def fore_chord(x):
    # 128x64: narrow root, widening outwards, then the outer margin slants back up to a
    # rounded apex on the leading edge
    if x < 88:
        return 24 + 37 * (x / 88) ** 0.7
    return 61 * math.sqrt(max(0.0, 1 - ((x - 88) / 40) ** 2))

def hind_chord(x):
    # 96x64 rounded fan
    return 58 * math.sqrt(max(0.0, 1 - (x / 96) ** 2)) + 3

def fore_base(x, y, c):
    if 0.30 * c < y < 0.58 * c and x < 112:
        return YELLOW                      # yellow band across the wing
    if y > 0.8 * c:
        return shade(ORANGE, -30)          # darker trailing edge
    return ORANGE

def hind_base(x, y, c):
    return YELLOW if y < 0.7 * c else ORANGE

def fur(base, stripe=None, period=8):
    def fn(x, y):
        c = stripe if stripe and (y // period) % 2 else base
        return shade(c, rng.randint(-14, 14) - (10 if (x + y * 3) % 5 == 0 else 0))
    return fn

def eye(x, y):
    facet = (x % 16 == 0) or (y % 16 == 0)  # 4x4 facets: stays readable from far away
    d = math.hypot(x - 31.5, y - 31.5) / 45
    return shade(BLUE, -40 if facet else int(60 - d * 80))

def antenna(x, y):
    # feathery: shaft along x (root -> tip) with chunky barbs, gaps transparent
    d = abs(y - 31.5)
    if d < 5:
        return shade(WHITE, -20)
    if (x + d * 0.5) % 12 < 6 and d < 31 - x * 0.3:
        return shade(WHITE, rng.randint(-10, 5))
    return None

tile(FOREWING, wing(128, fore_chord, (84, 26), 14, fore_base))
tile(HINDWING, wing(96, hind_chord, (44, 26), 9, hind_base))
tile(FUR_BROWN, fur(BROWN, shade(WHITE, -30)))
tile(FUR_WHITE, fur(WHITE))
tile(ABD_TAN, fur((190, 140, 80)))
tile(ABD_CREAM, fur((235, 215, 170)))
tile(EYE, eye)
tile(ANTENNA, antenna)
tile(LEG, fur((70, 45, 30)))
tile(FUR_ORANGE, fur((214, 120, 40)))

img.save(sys.argv[1])
print("WROTE", sys.argv[1])
