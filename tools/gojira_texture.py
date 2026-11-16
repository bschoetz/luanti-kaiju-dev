# Generates kaiju/gojira/textures/gojira.png, the 256x256 atlas (4x4 tiles of 64px) used by
# tools/gojira_model.py. Tile order must match the constants there.
#   python3 tools/gojira_texture.py kaiju/gojira/textures/gojira.png
import random, sys
from PIL import Image

T = 64
rng = random.Random(7)  # deterministic output
img = Image.new("RGBA", (4 * T, 4 * T), (40, 45, 40, 255))  # neutral filler: nothing ugly to bleed under filtering
px = img.load()

def clamp(c):
    return tuple(max(0, min(255, int(v))) for v in c)

def shade(c, d):
    return clamp(v + d for v in c)

def tile(index, fn):
    ox, oy = (index % 4) * T, (index // 4) * T
    for y in range(T):
        for x in range(T):
            px[ox + x, oy + y] = clamp(fn(x, y)) + (255,)
    return ox, oy

def put(index, x, y, c):
    if 0 <= x < T and 0 <= y < T:
        px[(index % 4) * T + x, (index // 4) * T + y] = clamp(c) + (255,)

def rough_skin(index, base):
    # mottled base + raised keloid bumps: lit top-left, shadowed bottom-right
    tile(index, lambda x, y: shade(base, rng.randint(-7, 7)))
    for _ in range(170):
        cx, cy, r = rng.randrange(T), rng.randrange(T), rng.choice((1, 2, 2, 3))
        lift = rng.randint(10, 24)
        for dy in range(-r - 1, r + 2):
            for dx in range(-r - 1, r + 2):
                d2 = dx * dx + dy * dy
                if d2 <= r * r:
                    put(index, cx + dx, cy + dy, shade(base, lift - (dx + dy) * 3))
                elif d2 <= (r + 1) ** 2 and dx + dy > 0:
                    put(index, cx + dx, cy + dy, shade(base, -18))

SKIN, SKIN_DARK, BELLY, PLATE, EYE, TOOTH, MOUTH, TONGUE, CLAW, BLACK, SOCKET, PLATE_TIP = range(12)

rough_skin(SKIN, (64, 74, 62))
rough_skin(SKIN_DARK, (34, 39, 35))
tile(BELLY, lambda x, y: shade((96, 98, 82) if y % 6 not in (0, 5) else (64, 68, 56),
                               rng.randint(-5, 5) - (8 if x % 16 == 0 else 0)))
tile(PLATE, lambda x, y: shade((205, 200, 184), rng.randint(-8, 8) - (35 if x % 6 == 0 else 0) - y // 6))
tile(PLATE_TIP, lambda x, y: shade((228, 226, 212), rng.randint(-6, 6) - (25 if x % 6 == 0 else 0)))

def eye(x, y):
    # coarse 16x16 design (4px cells) so it survives minification: rim, iris, fat slit pupil
    cx, cy = x // 4, y // 4
    if cx in (0, 15) or cy in (0, 15):
        return (25, 15, 8)                                  # dark rim
    if cx in (7, 8) or (cx in (6, 9) and 5 <= cy <= 10):
        return (12, 6, 4)                                   # slit pupil, 8-16px wide
    d = max(abs(cx - 7.5), abs(cy - 7.5))
    return shade((255, 210, 40), -int(d * 9))               # iris, darker outwards
tile(EYE, eye)
tile(TOOTH, lambda x, y: shade((238, 232, 210), rng.randint(-6, 6) - y // 4))
tile(MOUTH, lambda x, y: shade((120, 24, 30), rng.randint(-12, 12)))
tile(TONGUE, lambda x, y: shade((170, 60, 70), rng.randint(-10, 10)))
tile(CLAW, lambda x, y: shade((205, 195, 170), rng.randint(-6, 6) - y // 3))
tile(BLACK, lambda x, y: (10, 10, 10))
tile(SOCKET, lambda x, y: shade((22, 24, 22), rng.randint(-4, 4)))

img.save(sys.argv[1])
print("WROTE", sys.argv[1])
