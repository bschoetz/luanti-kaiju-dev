# Builds kaiju/ghidorah/models/ghidorah.glb (blocky skinned + animated three-headed dragon).
#   blender -b --factory-startup --python tools/ghidorah_model.py -- kaiju/ghidorah/models/ghidorah.glb
# Same conventions as tools/gojira_model.py and tools/mothra_model.py:
#   * Blender Z-up, model faces +Y; 10 units = 1 node at visual_size 1 (the mob uses 7.5, so
#     1 unit = 0.75 node); scene fps 1, so glTF seconds == frame numbers.
#   * Rigid skinning: every box belongs 100% to one bone; boxes overlap at joints.
#   * One 256x256 atlas, see tools/ghidorah_texture.py (RECTS must match).
#   * _l = +X side, _r = -X side (a side label, not anatomy).
# ghidorah/init.lua relies on the bone names, the frame ranges and the numbers printed by the
# self-check at the end.
import bpy, bmesh, sys, math, random, json, struct
from mathutils import Euler, Vector, Quaternion, Matrix

out = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)
scn = bpy.context.scene
scn.render.fps = 1

(SCALES, SCALES_DARK, BELLY, CROWN, MEMBRANE, MEMBRANE_ARM, CRESCENT, FAN, EYE, MOUTH,
 IVORY, CLAW, BLACK) = range(13)
RECTS = {SCALES: (0, 0, 64, 64), SCALES_DARK: (64, 0, 64, 64), BELLY: (128, 0, 64, 64),
         CROWN: (192, 0, 64, 64),
         MEMBRANE: (0, 64, 96, 64), MEMBRANE_ARM: (96, 64, 64, 64),
         CRESCENT: (160, 64, 64, 32), FAN: (160, 96, 64, 32),
         EYE: (224, 64, 32, 32), MOUTH: (224, 96, 32, 32),
         IVORY: (0, 128, 64, 64), CLAW: (64, 128, 64, 64), BLACK: (128, 128, 32, 32)}
FIT_TILES = {EYE, CRESCENT}   # mapped whole
ATLAS, DENSITY = 256, 4
rng = random.Random(42)
SIDES = ((1, "_l"), (-1, "_r"))
HEADS = ("c", "l", "r")

def V(*p):
    return Vector(p)

def mir(p, s):
    return Vector((p[0] * s, p[1], p[2]))

# --- skeleton (armature space) --------------------------------------------------
BONES = {}  # name: (head, tail, parent)

def bone(name, head, tail, parent=None):
    BONES[name] = (Vector(head), Vector(tail), parent)

bone("root", (0, 0, 0), (0, 0, 2))
bone("hips", (0, 0, 8.0), (0, 0.3, 10.6), "root")
bone("chest", (0, 0.3, 10.6), (0, 1.5, 15.5), "hips")

# Necks: point lists from the base to the head joint. The centre neck sits forward and
# higher; the side necks splay ~25 deg outwards.
# head_X and its parent neck_X4 both point exactly along +Y (roll 0), so their local axes are
# the model axes at rest. Luanti composes a relative set_bone_override rotation as
# "animation first, then override" (src/activeobject.h), i.e. about the PARENT's axes, so it
# is neck_X4's frame that matters for aiming. Skinning is rigid, so only a bone's head (the
# pivot) affects the mesh; where its tail points is free.
# Measured in the client (tests/ghidorah_show, scenes 12-14, Luanti 5.17), for
# set_bone_override("head_X", {rotation = {vec = v, absolute = false}}):
#   v.x > 0 pitches the nose DOWN, v.y > 0 rolls the +X (_l) side down,
#   v.z > 0 turns the nose towards the +X (_l) side (clockwise seen from above).
NECK = {"c": [V(0, 2.0, 15.9), V(0, 2.9, 17.8), V(0, 3.0, 19.7), V(0, 3.6, 21.5), V(0, 5.0, 22.7)],
        "l": [V(2.5, 1.4, 15.5), V(3.5, 2.0, 17.2), V(4.5, 2.2, 18.9), V(5.4, 2.8, 20.5), V(6.0, 4.2, 21.6)]}
NECK["r"] = [mir(p, -1) for p in NECK["l"]]
NECK_W = {"c": (3.0, 2.8, 2.6, 2.4), "l": (2.7, 2.5, 2.3, 2.1), "r": (2.7, 2.5, 2.3, 2.1)}
HEAD_SCALE = {"c": 1.0, "l": 0.86, "r": 0.86}
MOUTH_OFS = V(0, 5.8, -0.5)   # mouth opening relative to the head joint, times HEAD_SCALE
for t in HEADS:
    p = NECK[t]
    for i in range(4):
        tail = p[i + 1] if i < 3 else p[i] + V(0, (p[i + 1] - p[i]).length, 0)
        bone(f"neck_{t}{i + 1}", p[i], tail, "chest" if i == 0 else f"neck_{t}{i}")
    sc = HEAD_SCALE[t]
    bone("head_" + t, p[4], p[4] + V(0, 4, 0) * sc, f"neck_{t}4")
    bone("jaw_" + t, p[4] + V(0, 0.6, -0.8) * sc, p[4] + V(0, 4.6, -0.8) * sc, "head_" + t)

LEG = {}
WING = {}
WING_Z = 15.4
F_ANG, F_LEN = (5, -35, -68), (11.2, 12.5, 12.0)   # finger directions (deg from +X) and lengths
for s, sfx in SIDES:
    # legs hang from root (not hips) so a hip bob doesn't push the feet into the ground
    H, K, A, T = mir((2.8, 0, 8.0), s), mir((3.0, 1.6, 4.5), s), mir((3.0, -0.4, 1.3), s), mir((3.0, 3.4, 0.6), s)
    LEG[s] = (H, K, A, T)
    bone("thigh" + sfx, H, K, "root")
    bone("shin" + sfx, K, A, "thigh" + sfx)
    bone("foot" + sfx, A, T, "shin" + sfx)
    # wings are modelled spread flat (horizontal); every animation poses them
    S, E, W = mir((3.2, -1.6, WING_Z), s), mir((8.8, -1.2, WING_Z), s), mir((14.2, 0.0, WING_Z), s)
    tips = [W + mir((l * math.cos(math.radians(a)), l * math.sin(math.radians(a)), 0), s) for a, l in zip(F_ANG, F_LEN)]
    WING[s] = (S, E, W, tips)
    w = "wing" + sfx
    bone(w + "_upper", S, E, "chest")
    bone(w + "_fore", E, W, w + "_upper")
    for i in range(3):
        bone(f"{w}_f{i + 1}", W, tips[i], w + "_fore")

# Two tails: level at the base, sagging towards the ground, tips slightly raised, splayed.
TAIL = {}
for s, t in ((1, "a"), (-1, "b")):
    ys, zs = (-2.4, -6.4, -10.4, -14.4, -18.2, -21.8), (8.4, 7.7, 6.2, 4.4, 3.1, 3.3)
    TAIL[t] = [V(s * (1.3 + 0.2 * (-y - 2.4)), y, z) for y, z in zip(ys, zs)]
    for i in range(5):
        bone(f"tail_{t}{i + 1}", TAIL[t][i], TAIL[t][i + 1], "hips" if i == 0 else f"tail_{t}{i}")
TAIL_W = (3.0, 2.5, 2.0, 1.5, 1.1)

# --- geometry ---------------------------------------------------------------------
boxes = []  # (center, size, quat, bone, tile, {face: tile}, only, plate_flip or None)

def box(c, s, b, tile=SCALES, rot=(0, 0, 0), only=None, **faces):
    q = Euler(tuple(math.radians(a) for a in rot), "XYZ").to_quaternion()
    boxes.append((Vector(c), tuple(s), q, b, tile, faces, only, None))

def seg(p0, p1, w, h, b, tile=SCALES, ext=0.3, **faces):
    """Box running from p0 to p1 (local Y), w wide (local X), h thick (local Z = the side
    nearest to up; for a neck that is its back, so `bottom` is the throat)."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    q = d.normalized().to_track_quat("Y", "Z")
    boxes.append(((p0 + p1) / 2, (w, d.length + 2 * ext, h), q, b, tile, faces, None, None))

def plate(origin, along, across, length, width, b, tile, dz=0.0):
    """Thin alpha-textured plate: starts at origin, runs `length` along `along` and `width`
    along `across`. Only the two big faces are emitted. Tile x = along, tile y = across."""
    y = Vector(along).normalized()
    a = Vector(across).normalized()
    flip = a.cross(y).z < 0          # keep the local frame right-handed with Z up
    x = -a if flip else a
    q = Matrix((x, y, x.cross(y))).transposed().to_quaternion()
    c = Vector(origin) + y * length / 2 + a * width / 2 + V(0, 0, dz)
    boxes.append((c, (width, length, 0.06), q, b, tile, {}, ("top", "bottom"), flip))

def spike(base, h, b, l=0.9, lean=25):
    box(Vector(base) + V(0, 0, h * 0.4), (0.5, l, h), b, CROWN, rot=(lean, 0, 0))

# Legs: thick thighs, forward knees, three clawed toes and a rear spur
for s, sfx in SIDES:
    H, K, A, T = LEG[s]
    seg(H + V(0, 0, 0.8), K, 3.8, 4.2, "thigh" + sfx)
    seg(H + V(0.3 * s, 0.4, 0.2), K + V(0.3 * s, 0.2, 0.8), 3.4, 3.6, "thigh" + sfx, SCALES_DARK)
    box(K + V(0, 0.3, 0), (2.9, 2.6, 2.8), "thigh" + sfx)
    seg(K, A, 2.6, 2.8, "shin" + sfx)
    box(A + V(0, 0, 0.1), (2.8, 2.0, 1.8), "foot" + sfx, SCALES_DARK)
    box((A.x, 1.3, 0.7), (3.6, 4.4, 1.4), "foot" + sfx, SCALES_DARK)   # (a black sole reads as a hole in "die")
    box((A.x - 1.6 * s, -1.4, 0.4), (0.6, 1.0, 0.6), "foot" + sfx, CLAW, rot=(-15, 0, 0))
    for dx in (-1.15, 0, 1.15):
        box((A.x + dx, 3.9, 0.55), (0.95, 1.6, 1.0), "foot" + sfx, SCALES_DARK)
        box((A.x + dx, 5.0, 0.4), (0.6, 1.0, 0.7), "foot" + sfx, CLAW, rot=(-20, 0, 0))

# Torso: upright with a slight forward hunch, ribbed lighter belly, dorsal spikes
box((0, -0.2, 9.0), (7.0, 5.6, 3.8), "hips", bottom=BELLY)
box((0, 0.5, 12.0), (7.4, 5.8, 4.4), "chest", rot=(-8, 0, 0))
box((0, 1.2, 14.8), (6.8, 5.0, 3.0), "chest", rot=(-14, 0, 0))
box((0, 2.75, 9.1), (4.8, 0.3, 3.0), "hips", BELLY)
box((0, 3.45, 11.9), (5.0, 0.3, 3.8), "chest", BELLY, rot=(-8, 0, 0))
box((0, 3.75, 14.6), (4.4, 0.3, 2.6), "chest", BELLY, rot=(-14, 0, 0))
for s in (1, -1):
    box((3.75 * s, 0.1, 10.6), (0.6, 4.4, 3.6), "chest", SCALES_DARK, rot=(-8, 0, 0))   # flank
    box(WING[s][0] + V(0, 0.3, 0), (2.4, 2.4, 2.4), "chest", SCALES_DARK)               # shoulder
for b, y, z, h in (("hips", -3.0, 9.6, 1.6), ("chest", -2.5, 11.6, 2.0), ("chest", -2.0, 13.4, 2.0), ("chest", -1.4, 15.2, 1.6)):
    spike((0, y, z), h, b)

# Necks: four overlapping segments each, throat scales underneath. The end of neck_X4 is
# flesh-coloured: it is what remains visible when head_X is scaled to 0 (severed head).
for t in HEADS:
    p, w = NECK[t], NECK_W[t]
    for i in range(4):
        b = f"neck_{t}{i + 1}"
        if i < 3:
            seg(p[i], p[i + 1], w[i], w[i] * 0.95, b, ext=0.4, bottom=BELLY)
        else:
            seg(p[i], p[i + 1], w[i], w[i] * 0.95, b, ext=0.15, bottom=BELLY, front=MOUTH)
        d = (p[i + 1] - p[i]).normalized()
        back = d.cross(V(1, 0, 0)).normalized() * (w[i] * 0.45)      # the dorsal side
        spike((p[i] + p[i + 1]) / 2 - back * (1 if back.y > 0 else -1) + V(0, 0, -0.2), 1.1, b, l=0.8, lean=40)

def head(t, kind):
    """Skull + snout on head_X, lower jaw on jaw_X, red eyes, fangs, horns and crescent."""
    N, sc, hb, jb = NECK[t][4], HEAD_SCALE[t], "head_" + t, "jaw_" + t
    P = lambda x, y, z: N + V(x, y, z) * sc
    S = lambda *d: tuple(v * sc for v in d)
    box(P(0, 1.2, 0.5), S(3.4, 3.6, 2.6), hb, bottom=MOUTH)                 # skull
    box(P(0, 4.3, 0.2), S(2.6, 3.0, 1.6), hb, bottom=MOUTH)                 # snout
    box(P(0, 6.0, 0.1), S(2.0, 0.5, 1.2), hb)                               # nose
    box(P(0, 0.4, 1.95), S(2.4, 2.0, 0.4), hb, SCALES_DARK)
    for s in (1, -1):
        box(P(1.1 * s, 2.7, 1.75), S(1.5, 1.7, 0.55), hb, SCALES_DARK, rot=(0, 0, 10 * s))  # brow
        box(P(1.72 * s, 2.2, 0.95), S(0.12, 1.4, 0.9), hb, BLACK)                            # socket
        box(P(1.83 * s, 2.2, 0.95), S(0.1, 1.1, 0.65), hb, EYE)
        box(P(0.5 * s, 6.27, 0.4), S(0.35, 0.1, 0.25), hb, BLACK)                            # nostril
        for y in (3.3, 4.1, 4.9):
            box(P(1.12 * s, y, -0.75), S(0.3, 0.3, 0.5), hb, IVORY)
        box(P(0.95 * s, 5.75, -0.85), S(0.36, 0.36, 0.8), hb, IVORY)                         # fang
        for y in (3.7, 4.5, 5.2):
            box(P(0.95 * s, y, -0.55), S(0.26, 0.26, 0.42), jb, IVORY)
    box(P(0, 3.4, -1.15), S(2.4, 5.2, 0.8), jb, top=MOUTH)                  # lower jaw
    box(P(0, 1.5, -1.45), S(2.7, 2.2, 0.9), jb)                             # chin / hinge
    # crescent plate upright on the forehead, leaning back
    cw = 3.8 if kind == "crown" else 2.6
    box(P(0, 0.9, 2.0 + cw * 0.25), S(cw, 0.1, cw * 0.5), hb, CRESCENT, rot=(-20, 0, 0), only=("front", "back"))
    for s in (1, -1):
        if kind == "crown":          # the biggest, swept-back horns plus a smaller pair
            seg(P(1.0 * s, 0.6, 1.5), P(2.0 * s, -2.2, 2.9), 0.9 * sc, 0.9 * sc, hb, IVORY, ext=0.15)
            seg(P(2.0 * s, -2.2, 2.9), P(2.4 * s, -4.2, 3.9), 0.6 * sc, 0.6 * sc, hb, IVORY, ext=0.15)
            seg(P(1.5 * s, 1.4, 1.2), P(3.0 * s, -0.8, 2.2), 0.55 * sc, 0.55 * sc, hb, IVORY, ext=0.1)
        elif kind == "straight":     # left head: straight horns
            seg(P(1.0 * s, 0.6, 1.5), P(1.9 * s, -2.6, 3.5), 0.7 * sc, 0.7 * sc, hb, IVORY, ext=0.15)
        else:                        # right head: curved horns, the outer one chipped off
            seg(P(1.0 * s, 0.6, 1.5), P(1.9 * s, -1.6, 2.4), 0.75 * sc, 0.75 * sc, hb, IVORY, ext=0.15)
            if s > 0:
                seg(P(1.9 * s, -1.6, 2.4), P(2.1 * s, -2.6, 4.0), 0.5 * sc, 0.5 * sc, hb, IVORY, ext=0.15)

head("c", "crown")
head("l", "straight")
head("r", "chipped")

# Wings: arm + forearm + wrist claw + three fingers; membrane panels are thin plates, each
# rigid on one bone. Panels sit 0.12 apart in height so they don't z-fight when the fan closes.
for s, sfx in SIDES:
    S, E, W, tips = WING[s]
    w = "wing" + sfx
    back = lambda d: Vector((d.y * s, -d.x * s, 0)).normalized()   # in-plane, towards the trailing edge
    seg(S, E, 1.5, 1.5, w + "_upper", SCALES_DARK)
    seg(E, W, 1.2, 1.2, w + "_fore", SCALES_DARK)
    box(E, (1.7, 1.7, 1.7), w + "_upper", SCALES_DARK)
    seg(W + V(0, 0.2, 0), W + V(0.6 * s, 1.8, 0.2), 0.5, 0.5, w + "_fore", CLAW, ext=0.1)   # wrist claw
    plate(S + (E - S) * 0.08, E - S, back(E - S), (E - S).length * 1.0, 9.0, w + "_upper", MEMBRANE_ARM, -0.24)
    plate(E, W - E, back(W - E), (W - E).length * 1.08, 10.5, w + "_fore", MEMBRANE_ARM, -0.12)
    for i, (tip, width) in enumerate(zip(tips, (8.0, 6.6, 4.6))):
        b = f"{w}_f{i + 1}"
        seg(W, tip, 0.55, 0.55, b, SCALES_DARK, ext=0.1)
        box(tip, (0.5, 0.5, 0.5), b, CLAW)
        plate(W, tip - W, back(tip - W), (tip - W).length, width, b, MEMBRANE, 0.24 - 0.12 * i)

# Tails: tapering segments, belly scales underneath, a small spiky fan at each tip
for t in ("a", "b"):
    p = TAIL[t]
    for i in range(5):
        w = TAIL_W[i]
        seg(p[i], p[i + 1], w, w * 0.92, f"tail_{t}{i + 1}", ext=0.45, bottom=BELLY)
        if i < 4:
            spike((p[i] + p[i + 1]) / 2 + V(0, 0, w * 0.4), 1.3 - i * 0.15, f"tail_{t}{i + 1}", l=0.8, lean=30)
    d = (p[5] - p[4]).normalized()
    side = d.cross(V(0, 0, 1)).normalized()
    plate(p[5] - d * 0.6 - side * 2.4, d, side, 5.2, 4.8, f"tail_{t}5", FAN)
    up = side.cross(d)
    plate(p[5] - d * 0.6 - up * 1.6, d, up, 4.4, 3.2, f"tail_{t}5", FAN)   # upright one: readable from the side

# --- build mesh ---------------------------------------------------------------------
CORNERS = [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),
           (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]
FACES = {  # corner indices, and which local axes (u, v) the texture follows
    "bottom": ((0, 3, 2, 1), (0, 1)), "top": ((4, 5, 6, 7), (0, 1)),
    "front": ((3, 7, 6, 2), (0, 2)), "back": ((0, 1, 5, 4), (0, 2)),
    "right": ((1, 2, 6, 5), (1, 2)), "left": ((0, 4, 7, 3), (1, 2)),
}

def face_uvs(tile, local, axes, plate_flip):
    a, b = axes
    us = [p[a] for p in local]; vs = [p[b] for p in local]
    du, dv = max(us) - min(us), max(vs) - min(vs)
    tx, ty, tw, th = RECTS[tile]
    res = []
    if plate_flip is not None:
        # plate: tile x runs along local Y, tile y along `across` (local X, or -X if flipped)
        for u, v in zip(us, vs):
            fa = (v - min(vs)) / dv
            fc = (u - min(us)) / du
            if plate_flip:
                fc = 1 - fc
            res.append(((tx + 0.5 + fa * (tw - 1)) / ATLAS, 1 - (ty + 0.5 + fc * (th - 1)) / ATLAS))
        return res
    if tile in FIT_TILES:
        w, h = tw - 1, th - 1; ox = oy = 0.5
    else:
        w, h = min(du * DENSITY, tw - 1), min(dv * DENSITY, th - 1)
        ox, oy = rng.uniform(0.5, tw - 0.5 - w), rng.uniform(0.5, th - 0.5 - h)
    for u, v in zip(us, vs):
        fu = (u - min(us)) / du if du else 0
        fv = (v - min(vs)) / dv if dv else 0
        res.append(((tx + ox + fu * w) / ATLAS, 1 - (ty + oy + (1 - fv) * h) / ATLAS))  # image y grows downwards
    return res

verts, faces, uvs, vert_bone = [], [], [], []
for c, s, q, b, tile, overrides, only, pflip in boxes:
    base = len(verts)
    local = [Vector((cx * s[0] / 2, cy * s[1] / 2, cz * s[2] / 2)) for cx, cy, cz in CORNERS]
    for p in local:
        verts.append(tuple(c + q @ p)); vert_bone.append(b)
    for name, (idx, axes) in FACES.items():
        if only and name not in only:
            continue
        faces.append(tuple(base + k for k in idx))
        uvs.append(face_uvs(overrides.get(name, tile), [local[k] for k in idx], axes, pflip))

me = bpy.data.meshes.new("ghidorah")
me.from_pydata(verts, [], faces)
uv = me.uv_layers.new(name="UVMap")
for poly, fuv in zip(me.polygons, uvs):
    for li, co in zip(poly.loop_indices, fuv):
        uv.data[li].uv = co
bm = bmesh.new(); bm.from_mesh(me)
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bm.to_mesh(me); bm.free()
me.update()

obj = bpy.data.objects.new("ghidorah", me)
scn.collection.objects.link(obj)
me.materials.append(bpy.data.materials.new("ghidorah"))

# --- armature -------------------------------------------------------------------------
arm_data = bpy.data.armatures.new("Armature")
arm = bpy.data.objects.new("Armature", arm_data)
scn.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
for name, (h, t, _) in BONES.items():
    eb = arm_data.edit_bones.new(name); eb.head, eb.tail = h, t
    if name.startswith("head_") or name[:5] == "neck_" and name[-1] == "4":
        eb.roll = 0   # bone along +Y, roll 0: local axes == model axes
for name, (_, _, p) in BONES.items():
    if p:
        arm_data.edit_bones[name].parent = arm_data.edit_bones[p]
bpy.ops.object.mode_set(mode="OBJECT")

for name in BONES:
    obj.vertex_groups.new(name=name)
for i, b in enumerate(vert_bone):
    obj.vertex_groups[b].add([i], 1.0, "REPLACE")
obj.parent = arm
obj.modifiers.new("Armature", "ARMATURE").object = arm

# --- animation ------------------------------------------------------------------------
# Rotations are armature-space degrees (or a Quaternion), relative to the parent's posed
# frame, pivoting at the bone head:
#   X = pitch: + lifts what lies ahead (+Y) of the pivot and swings a hanging leg forward;
#       for a bone pointing backwards (tails) + moves the tip down.
#   Y = roll:  + moves the +X side down. Wings go through wings(), which hides the sign.
#   Z = yaw:   + turns +X towards +Y, i.e. the nose swings towards the -X (_r) side.
# loc = offset in armature units.
for pb in arm.pose.bones:
    pb.rotation_mode = "QUATERNION"

def R(axis, deg):
    return Quaternion({"X": (1, 0, 0), "Y": (0, 1, 0), "Z": (0, 0, 1)}[axis], math.radians(deg))

def key(frame, loc=None, **rots):
    loc = loc or {}
    for name in BONES:
        pb = arm.pose.bones[name]
        rest = pb.bone.matrix_local.to_quaternion()
        r = rots.get(name, (0, 0, 0))
        q = r if isinstance(r, Quaternion) else Euler(tuple(math.radians(a) for a in r), "XYZ").to_quaternion()
        pb.rotation_quaternion = rest.inverted() @ q @ rest
        pb.location = rest.inverted() @ Vector(loc.get(name, (0, 0, 0)))
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        pb.keyframe_insert("location", frame=frame)

TAU = 2 * math.pi
sin, cos = math.sin, math.cos

def lerp(u, pts):
    """Piecewise-linear (smoothstepped) curve through (time, value) points."""
    if u <= pts[0][0]:
        return pts[0][1]
    for (t0, v0), (t1, v1) in zip(pts, pts[1:]):
        if u <= t1:
            k = (u - t0) / (t1 - t0)
            k = k * k * (3 - 2 * k)
            return v0 + (v1 - v0) * k
    return pts[-1][1]

def both(prefix, l, r=None):
    return {prefix + "_l": l, prefix + "_r": r if r is not None else l}

def wings(up, fold, tilt=0.0, sweep=0.0, pre=0.0, up_r=None, fold_r=None):
    """up > 0 raises both wings (roll about the body's long axis; the +X wing needs a
    negative Y roll to rise, see mothra/README.md 5.4).
    fold 0 = fully spread fan, 1 = closed: the upper arm swings back, the forearm forwards
    and the fingers close towards the innermost one (all in the wing's own plane).
    tilt > 0 pitches the wing plane so the membrane hangs down behind the arm (90 = upright
    fan facing forwards); it is applied before the roll.
    sweep > 0 swings the whole wing forwards. pre is a final pitch in the chest's frame; it
    cancels the body's pitch in flight so the wings beat about a level axis."""
    d = {}
    for s, sfx in SIDES:
        u = up if s > 0 or up_r is None else up_r
        f = fold if s > 0 or fold_r is None else fold_r
        w = "wing" + sfx
        d[w + "_upper"] = R("X", pre) @ R("Y", -s * u) @ R("X", tilt) @ R("Z", s * (sweep - 30 * f))
        d[w + "_fore"] = (0, 0, s * 55 * f)
        for i, a in enumerate((125, 100, 78)):
            d[f"{w}_f{i + 1}"] = (0, 0, -s * a * f)
    return d

def neck(t, pitch, yaw=0.0, roll=0.0, head=(0, 0, 0), jaw=0.0):
    """pitch/yaw/roll: one value for all four neck bones or a list of four."""
    d = {}
    for i in range(4):
        g = lambda v: v[i] if isinstance(v, (list, tuple)) else v
        d[f"neck_{t}{i + 1}"] = (g(pitch), g(roll), g(yaw))
    d["head_" + t] = head
    d["jaw_" + t] = (jaw, 0, 0)
    return d

def tails(fn):
    """fn(i, phase_offset) -> (pitch, yaw) for tail bone i (1..5); tail b lags behind a."""
    d = {}
    for t, off, s in (("a", 0.0, 1), ("b", 1.9, -1)):
        for i in range(1, 6):
            p, y = fn(i, off)
            d[f"tail_{t}{i}"] = (p, 0, y)
    return d

def legs(thigh, shin, toe=0.0):
    """Both legs bent by the same angles, soles kept flat (+ toe). Returns the pose and how
    far the soles rise, i.e. how far root has to drop to keep them on the ground."""
    H, K, A, _ = LEG[1]
    def rz(v, deg):
        return v.y * sin(math.radians(deg)) + v.z * cos(math.radians(deg))
    lift = rz(K - H, thigh) + rz(A - K, thigh + shin) - (A - H).z
    pose = dict(**both("thigh", (thigh, 0, 0)), **both("shin", (shin, 0, 0)), **both("foot", (-(thigh + shin) + toe, 0, 0)))
    return pose, lift

WINGS_REST = dict(up=42, fold=0.62, tilt=72)

def stand_pose(t):
    """The idle pose at phase t; t = 0 is the neutral pose every one-shot clip starts/ends in."""
    br = sin(t)
    p = {}
    # centre: steady, slow and small
    p.update(neck("c", [1.5 * sin(t - i * 0.4) for i in range(4)], [1.5 * sin(t + 1 - i * 0.3) for i in range(4)],
                  head=(-2 * sin(t - 1.6), 0, 0), jaw=-2 - 2 * br))
    # left: curious, big slow sweeps and a tilted head
    p.update(neck("l", [3 * sin(t + 2 - i * 0.6) for i in range(4)], [5 * sin(t + 0.5 - i * 0.5) for i in range(4)],
                  head=(4 * sin(2 * t), 9 * sin(t + 1), 8 * sin(t - 1.2)), jaw=-3 - 3 * sin(2 * t + 1)))
    # right: twitchy, small fast jerks
    p.update(neck("r", [2 * sin(3 * t - i * 0.9) for i in range(4)], [2.5 * sin(4 * t + 1 - i * 0.7) for i in range(4)],
                  head=(3 * sin(6 * t), 0, 5 * sin(3 * t + 2)), jaw=-4 - 4 * max(0, sin(3 * t))))
    p.update(wings(WINGS_REST["up"] + 2.5 * br, WINGS_REST["fold"] - 0.03 * br, WINGS_REST["tilt"]))
    p.update(tails(lambda i, off: (0, 6 * sin(t + off - i * 0.5))))
    p["chest"] = (1.5 * br, 0, 0)
    return p

NEUTRAL = stand_pose(0)

def P(**over):
    return dict(NEUTRAL, **over)

# stand 0-60
for f in range(0, 61, 2):
    key(f, **stand_pose(TAU * f / 60))

# walk 70-110: one full stride cycle (left + right step), same scheme as gojira's fixed walk.
# Stance: the sole moves backwards at constant speed and root drops by however much the
# ankle's arc lifts the sole (plants the foot, gives the bob). Swing: eased return, knee bent.
# ghidorah/init.lua derives its walk animation speed from WALK_CYCLE_UNITS (printed below).
A = 22
LEG_V = LEG[1][2] - LEG[1][0]                           # hip -> ankle at rest
LEG_R = math.hypot(LEG_V.y, LEG_V.z)
LEG_PHI = math.degrees(math.atan2(-LEG_V.y, -LEG_V.z))  # thigh angle that puts the ankle under the hip
WALK_CYCLE_UNITS = 2 * 2 * LEG_R * sin(math.radians(A))
for f in range(70, 111):
    ph = TAU * (f - 70) / 40
    pose = {}
    drop = 0.0
    for s, sfx, off in ((1, "_l", 0), (-1, "_r", math.pi)):
        p = (ph + off) % TAU
        if p <= math.pi + 1e-9:                 # stance
            swing = 0.0
            rel = math.degrees(math.asin(sin(math.radians(A)) * (1 - 2 * p / math.pi)))
            drop = max(drop, -LEG_V.z - LEG_R * cos(math.radians(rel)))
        else:
            swing = -sin(p)                     # 0 at lift-off/landing, 1 mid-swing
            rel = A * cos(p)
        thigh = LEG_PHI + rel + 12 * swing
        shin = -38 * swing
        pose["thigh" + sfx] = (thigh, 0, 0)
        pose["shin" + sfx] = (shin, 0, 0)
        pose["foot" + sfx] = (-(thigh + shin) + 10 * swing, 0, 0)  # sole flat, toes lift in swing
    for t, off, amp in (("c", 0.0, 2.0), ("l", 1.3, 3.0), ("r", 2.6, 2.5)):   # necks bob with the steps
        pose.update(neck(t, [amp * cos(2 * ph + off - i * 0.5) for i in range(4)],
                         [1.5 * cos(ph + off - i * 0.4) for i in range(4)],
                         head=(-amp * 1.5 * cos(2 * ph + off - 1.5), 0, 2 * cos(ph)), jaw=-3))
    pose.update(wings(WINGS_REST["up"] + 3 * cos(2 * ph), WINGS_REST["fold"] + 0.02 * cos(2 * ph), WINGS_REST["tilt"], sweep=2 * sin(2 * ph)))
    pose.update(tails(lambda i, off: (-1.0, 8 * sin(ph + off - i * 0.6))))
    key(f, loc={"root": (0, 0, -drop)}, hips=(-3, 3 * sin(ph), 5 * cos(ph)), chest=(-2, -2 * sin(ph), -6 * cos(ph)), **pose)

# Flight poses. BODY is the forward lean (hips + chest); the necks, wings and tails undo it.
def air_pose(ph, hips, chest, amp, mid, fold, tilt, leg, weave):
    lean = hips + chest
    up = mid + amp * cos(ph)                               # ph 0 = top of the upstroke
    p = dict(hips=(hips, 0, 0), chest=(chest, 0, 0))
    p.update(legs(*leg)[0])
    # wings fold a little on the way up and twist with the stroke; the body's lean is undone
    p.update(wings(up, fold * (0.5 - 0.5 * sin(ph)), tilt + 10 * sin(ph), pre=-lean))
    # necks reach forward: bent back up along the chain so the heads end up roughly level
    k = -lean / 52.0
    for t, off, a in (("c", 0.0, 1.0), ("l", 1.4, 1.5), ("r", 2.9, 1.2)):
        wv = weave * a
        p.update(neck(t, [-10 * k + wv * sin(ph + off), -6 * k + wv * sin(ph + off - 0.6), 12 * k, 18 * k],
                      [wv * 1.2 * sin(ph + off + 1 - i * 0.5) for i in range(4)],
                      head=(33 * k + 2 * sin(ph + off), 0, 0), jaw=-4))
    # tails trail behind: undo most of the lean, then a travelling wave
    p.update(tails(lambda i, off: ((-lean * 0.7 if i == 1 else 0) + 4 * sin(ph + off - i * 0.7), 3 * sin(ph + off - i * 0.5))))
    return p

FLY = dict(hips=-40, chest=-12, amp=38, mid=6, fold=0.22, tilt=0, leg=(-30, -55, 45), weave=1.5)
HOVER = dict(hips=-12, chest=-6, amp=30, mid=10, fold=0.15, tilt=22, leg=(-8, -25, 30), weave=3.0)

# fly 120-150: two full beats, the body rises on the downstroke
for f in range(120, 151):
    ph = TAU * (f - 120) / 15
    key(f, loc={"root": (0, 0, -0.6 * cos(ph - 0.8))}, **air_pose(ph, **FLY))
# hover 160-200: two slower beats, body more upright, necks weaving
for f in range(160, 201):
    ph = TAU * (f - 160) / 20
    key(f, loc={"root": (0, 0, -0.4 * cos(ph - 0.8))}, **air_pose(ph, **HOVER))
# beam_fly 410-450: the hover beat with steady necks and the jaws wide open (beams in flight)
for f in range(410, 451):
    ph = TAU * (f - 410) / 20
    p = air_pose(ph, **dict(HOVER, weave=0.5))
    for t in HEADS:
        p["jaw_" + t] = (-48, 0, 0)
    key(f, loc={"root": (0, 0, -0.4 * cos(ph - 0.8))}, **p)
HOVER0 = air_pose(0, **HOVER)
HOVER0_LOC = {"root": (0, 0, -0.4 * cos(-0.8))}

# bite 210-230: the heads lunge forward and snap one after the other (centre, left, right).
# The first snap comes early because mcl_mobs deals the damage when the animation starts.
for f in range(210, 231):
    p = {}
    for t, start in (("c", 0), ("l", 3), ("r", 6)):
        u = f - 210 - start
        g = lerp(u, [(0, 0), (2, -0.35), (5, 1), (7, 1), (13, 0)])        # lunge amount
        j = lerp(u, [(0, 0), (2, -30), (4, -48), (5, -45), (6, 0), (13, 0)])  # jaw
        p.update(neck(t, [-16 * g, -14 * g, -8 * g, 2 * g], head=(22 * g, 0, 0), jaw=j - 2))
    c = lerp(f - 210, [(0, 0), (2, 3), (6, -8), (12, -5), (20, 0)])
    key(f, **P(chest=(c, 0, 0), **p))

# beam 240-290: necks rear back, then all three aim forward with the jaws wide open and
# hold from 250 to 284 (the beams fire during the hold), wings spread wide; closes at the end.
def beam_pose(g, o, jit=0.0):
    """g: -1 = reared back, 1 = aiming; o: 0..1 wings spread and jaws open."""
    p = {}
    for t, a in (("c", 1.0), ("l", 0.9), ("r", 0.9)):
        if g < 0:
            p.update(neck(t, [-9 * g, -8 * g, -4 * g, -2 * g], head=(-10 * g, 0, 0), jaw=-12 * o - 2))
        else:
            p.update(neck(t, [-13 * g * a, -11 * g * a, -5 * g * a, 0], [jit * a, 0, -jit * a, 0],
                          head=(19 * g * a, 0, 0), jaw=-46 * o - 2))
    p.update(wings(WINGS_REST["up"] - 12 * o, WINGS_REST["fold"] * (1 - 0.92 * o), WINGS_REST["tilt"] + 8 * o))
    p["chest"] = (4 * max(0, -g) - 5 * max(0, g), 0, 0)
    p.update(tails(lambda i, off: (-2 * o, 6 * sin(off - i * 0.5) * (1 - o))))
    return P(**p)

key(240, **NEUTRAL)
key(246, **beam_pose(-1, 0.6))
for f in range(250, 285, 2):
    key(f, **beam_pose(1, 1, jit=1.2 * sin(f * 2.4)))
key(290, **NEUTRAL)

# takeoff 300-320: crouch, one huge downbeat while the legs extend, ends in the hover pose
crouch, crouch_lift = legs(38, -70)
key(300, **NEUTRAL)
key(306, loc={"root": (0, 0, -crouch_lift)}, **P(hips=(-8, 0, 0), chest=(-6, 0, 0), **crouch, **wings(72, 0.05, 30)))
stretch, stretch_lift = legs(-8, 12, toe=-35)
key(311, loc={"root": (0, 0, 1.5 - stretch_lift)}, **P(hips=(4, 0, 0), chest=(4, 0, 0), **stretch, **wings(-38, 0.0, 10)))
key(315, loc={"root": (0, 0, 1.0)}, **dict(HOVER0, **wings(-10, 0.2, 20, pre=18)))
key(320, loc=HOVER0_LOC, **HOVER0)

# land 330-350: starts in the hover pose, wings flare, legs reach down, crouch on impact
reach, reach_lift = legs(10, -8, toe=-15)
key(330, loc=HOVER0_LOC, **HOVER0)
key(337, loc={"root": (0, 0, 0.8)}, **dict(HOVER0, hips=(2, 0, 0), chest=(2, 0, 0), **reach, **wings(55, 0.0, 65)))
key(343, loc={"root": (0, 0, -crouch_lift)}, **P(hips=(-10, 0, 0), chest=(-8, 0, 0), **crouch, **wings(20, 0.25, 60)))
key(350, **NEUTRAL)

# die 360-400: knees buckle, he topples onto his +X side and lies ON the ground.
# Legs hang from root, so root drops by what the folded legs lift the soles; the roll is
# about the ground line through the origin, so root is then raised until the lowest vertex
# touches the ground (measured below, two passes).
buckle, buckle_lift = legs(35, -65)
def die_keys(lift388, lift400):
    key(360, **NEUTRAL)
    sag = {}
    for t in HEADS:
        sag.update(neck(t, [-10, -12, -10, -6], head=(-10, 0, 0), jaw=-20))
    key(370, loc={"root": (0, 0, -buckle_lift)}, **P(chest=(-10, 0, 0), **buckle, **sag, **wings(25, 0.5, 60)))
    # lying on the +X side: + roll on a neck lays it towards the ground (and - yaw, once it
    # is pitched forwards). The left neck is the low one, so it is bent away from the ground
    # (it would otherwise prop the body up); the right one droops across. Wings: the lower one is folded flat under/along the body, the upper
    # one flops over. Tails: yaw + droops them onto the ground.
    lying = dict(buckle, chest=(-6, 0, 0))
    lying.update(neck("c", [-14, -16, -12, -8], roll=[2, 3, 3, 2], head=(-12, 0, 0), jaw=-30))
    lying.update(neck("l", [-16, -14, -10, -8], roll=[-14, -6, 0, 0], yaw=[10, 9, 5, 0], head=(-6, 0, 0), jaw=-24))
    lying.update(neck("r", [-10, -12, -14, -10], roll=[14, 16, 16, 12], head=(-14, 20, 0), jaw=-36))
    lying.update(wings(93, 0.35, 0, up_r=112, fold_r=0.55))
    # tail a is the low one: lifted to flank level; tail b falls across onto the ground
    for i in range(1, 6):
        lying[f"tail_a{i}"] = (-1.0, 0, -7.0 if i == 1 else 0.5)
        lying[f"tail_b{i}"] = (-1.0, 0, 7.3 if i < 5 else 0.0)
    key(388, loc={"root": (0, 0, lift388)}, root=(0, 78, 0), **lying)
    key(400, loc={"root": (0, 0, lift400)}, root=(0, 90, 0), **lying)

def posed(frame):
    scn.frame_set(frame)
    dg = bpy.context.evaluated_depsgraph_get()
    return [v.co.copy() for v in obj.evaluated_get(dg).data.vertices]

die_keys(0, 0)
DIE_LIFT = [-min(v.z for v in posed(f)) for f in (388, 400)]
die_keys(*DIE_LIFT)

scn.frame_start, scn.frame_end = 0, 450
arm.animation_data.action.name = "ghidorah"

bpy.ops.export_scene.gltf(
    filepath=out, export_format="GLB", export_yup=True, export_apply=True,
    export_texcoords=True, export_normals=True,
    export_materials="EXPORT", export_image_format="NONE",
    export_skins=True, export_animations=True, export_animation_mode="ACTIONS",
    export_force_sampling=True, export_frame_range=False, export_anim_single_armature=True,
    export_def_bones=False, export_leaf_bone=False, export_morph=False,
    export_extras=False, export_cameras=False, export_lights=False,
)
print("WROTE", out, len(verts), "verts", len(boxes), "boxes", len(BONES), "bones")

# --- self-check, and the numbers ghidorah/init.lua needs -----------------------------------
UNIT = 0.75  # nodes per unit at visual_size 7.5

with open(out, "rb") as fh:
    glb = fh.read()
jlen = struct.unpack_from("<I", glb, 12)[0]
gltf = json.loads(glb[20:20 + jlen])
gl_verts = sum(gltf["accessors"][p["attributes"]["POSITION"]]["count"] for m in gltf["meshes"] for p in m["primitives"])
joints = [gltf["nodes"][j]["name"] for j in gltf["skins"][0]["joints"]]
print("glTF vertices %d (limit 65535), joints %d, bones %d" % (gl_verts, len(joints), len(BONES)))
assert gl_verts < 65535 and sorted(joints) == sorted(BONES), "vertex limit or bone list"
for name, (_, _, parent) in BONES.items():
    assert (arm_data.bones[name].parent.name if parent else None) == parent, name
print("bones:", " ".join(BONES))

for f in (0, 30):
    zs = [v.z for v in posed(f)]; xs = [v.x for v in posed(f)]
    print("stand frame %d: height %.2f (%.1f nodes), width %.2f, lowest %.2f" % (f, max(zs), max(zs) * UNIT, max(xs) - min(xs), min(zs)))
xs = [v[0] for v in verts]; zs = [v[2] for v in verts]
print("bind pose (wings spread flat): wingspan %.2f units (%.1f nodes)" % (max(xs) - min(xs), (max(xs) - min(xs)) * UNIT))
walk_min = [min(v.z for v in posed(f)) for f in range(70, 111, 5)]
print("WALK_CYCLE_UNITS %.3f (%.2f nodes); lowest vertex per walk frame: %s"
      % (WALK_CYCLE_UNITS, WALK_CYCLE_UNITS * UNIT, " ".join("%.2f" % z for z in walk_min)))
assert all(abs(z) < 0.15 for z in walk_min), "walk: stance foot not on the ground"
torso = [i for i, b in enumerate(vert_bone) if b in ("hips", "chest")]
for f in (370, 388, 400):
    vs = posed(f)
    zs = [v.z for v in vs]
    low = min(range(len(vs)), key=lambda i: vs[i].z)
    print("die frame %d: lowest vertex %.2f (%s), torso lowest %.2f, highest %.2f"
          % (f, min(zs), vert_bone[low], min(vs[i].z for i in torso), max(zs)))
    lows = {}
    for i, v in enumerate(vs):
        lows[vert_bone[i]] = min(lows.get(vert_bone[i], 99), v.z)
    print("   lowest bones:", " ".join("%s %.1f" % kv for kv in sorted(lows.items(), key=lambda kv: kv[1])[:10]))
print("die root lift: frame 388 %.2f, frame 400 %.2f" % tuple(DIE_LIFT))

def head_state(t):
    hb = arm.pose.bones["head_" + t]
    to_posed = hb.matrix @ hb.bone.matrix_local.inverted()
    mouth = to_posed @ (NECK[t][4] + MOUTH_OFS * HEAD_SCALE[t])
    joint = to_posed @ NECK[t][4]
    fwd = to_posed.to_quaternion() @ V(0, 1, 0)
    return mouth, joint, fwd

for label, frame in (("stand", 0), ("beam hold", 260), ("fly", 120), ("hover", 160), ("beam_fly", 410), ("beam_fly", 420)):
    scn.frame_set(frame)
    bpy.context.evaluated_depsgraph_get()
    for t in HEADS:
        m, j, fw = head_state(t)
        print("%-9s f%-3d head_%s mouth: forward %6.2f, sideways %6.2f, height %6.2f units (%.2f / %.2f / %.2f nodes); "
              "joint (%.2f, %.2f, %.2f); pitch %5.1f, yaw %5.1f deg"
              % (label, frame, t, m.y, m.x, m.z, m.y * UNIT, m.x * UNIT, m.z * UNIT, j.y, j.x, j.z,
                 math.degrees(math.asin(max(-1, min(1, fw.z)))), math.degrees(math.atan2(-fw.x, fw.y))))

# Head-axis report: which local axis of head_X does what. Local axes are those of the glTF
# node (what set_bone_override rotates about); they are read back from the exported file.
def gl_quat(node):
    x, y, z, w = node.get("rotation", (0, 0, 0, 1))
    return Quaternion((w, x, y, z))

parent_of = {c: i for i, n in enumerate(gltf["nodes"]) for c in n.get("children", ())}
def gl_world(i):
    q = gl_quat(gltf["nodes"][i])
    return gl_world(parent_of[i]) @ q if i in parent_of else q

to_blender = lambda v: Vector((v.x, -v.z, v.y))   # glTF (Y up, -Z forward) -> armature (Z up, +Y forward)
print("head axes at rest (glTF node local axis -> model direction; rotation by +10 deg about it, right-handed):")
for name in [n for t in HEADS for n in (f"neck_{t}4", "head_" + t)]:
    idx = next(i for i, n in enumerate(gltf["nodes"]) if n.get("name") == name)
    gw = gl_world(idx)
    for ax in ("X", "Y", "Z"):
        world_axis = to_blender(gw @ Vector({"X": (1, 0, 0), "Y": (0, 1, 0), "Z": (0, 0, 1)}[ax]))
        fwd = Quaternion(world_axis, math.radians(10)) @ V(0, 1, 0)
        up = Quaternion(world_axis, math.radians(10)) @ V(0, 0, 1)
        print("  %-7s local +%s = model (%5.2f, %5.2f, %5.2f): pitch %+5.1f (nose up +), yaw %+5.1f (nose to -X/_r side +), roll %+5.1f (+X/_l side down +)"
              % (name, ax, *world_axis, math.degrees(math.asin(fwd.z)), math.degrees(math.atan2(-fwd.x, fwd.y)),
                 math.degrees(math.asin(-up.x))))
# cross-check in Blender: pose the bone by a local rotation and compare the forward vector
scn.frame_set(0)
for t in HEADS:
    pb = arm.pose.bones["head_" + t]
    base_q = pb.rotation_quaternion.copy()
    res = []
    for ax in ("X", "Y", "Z"):
        pb.rotation_quaternion = base_q @ R(ax, 10)
        bpy.context.view_layer.update()
        fw = head_state(t)[2]
        res.append("+%s: pitch %+5.1f yaw %+5.1f" % (ax, math.degrees(math.asin(fw.z)), math.degrees(math.atan2(-fw.x, fw.y))))
    pb.rotation_quaternion = base_q
    bpy.context.view_layer.update()
    m, j, fw = head_state(t)
    print("  blender check head_%s (stand frame 0, base pitch %+.1f yaw %+.1f): %s"
          % (t, math.degrees(math.asin(fw.z)), math.degrees(math.atan2(-fw.x, fw.y)), "; ".join(res)))
