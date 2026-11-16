# Builds kaiju/cthulhu/models/cthulhu.glb (blocky skinned + animated Cthulhu).
#   blender -b --factory-startup --python tools/cthulhu_model.py -- kaiju/cthulhu/models/cthulhu.glb
# Same conventions as tools/gojira_model.py and tools/ghidorah_model.py:
#   * Blender Z-up, model faces +Y; 10 units = 1 node at visual_size 1. The mob uses
#     visual_size SCALE (6), so 1 unit = 0.6 node and he is about 13 nodes tall: short
#     enough to submerge completely in 15-32 node deep ocean.
#   * scene fps 1, so glTF seconds == frame numbers; one action, clips are frame ranges.
#   * Rigid skinning: every box belongs 100% to one bone; boxes overlap at joints.
#   * One 256x256 atlas, see tools/cthulhu_texture.py (RECTS must match).
#   * _l = +X side, _r = -X side (a side label, not anatomy).
#   * EVERY bone points along +Y with roll 0, so every bone's local axes are the model axes
#     at rest. A relative set_bone_override therefore turns any bone (head, feelers, claws)
#     about the model axes, in its parent's posed frame (see kaiju/cthulhu/README-model.md).
# Design: Lovecraft's 1934 sketch and the 1928 idol text (see README-model.md): hunched,
# pear-shaped scaly body, cephalopod head bent forward with a beard of 8 feelers, narrow
# folded wings whose hooks rise above the head, huge claws on hands and feet, no tail.
import bpy, bmesh, sys, math, random, json, struct
from mathutils import Euler, Vector, Quaternion, Matrix

out = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)
scn = bpy.context.scene
scn.render.fps = 1

SCALE = 6.0              # visual_size of the mob
UNIT = SCALE / 10        # nodes per unit

(SKIN, SKIN_DARK, BELLY, FEELER, WING, CLAW, EYE, SOCKET, CLAW_TIP) = range(9)
RECTS = {SKIN: (0, 0, 64, 64), SKIN_DARK: (64, 0, 64, 64), BELLY: (128, 0, 64, 64),
         FEELER: (192, 0, 64, 64), WING: (0, 64, 128, 32), CLAW: (128, 64, 64, 64),
         EYE: (192, 64, 32, 32), SOCKET: (224, 64, 32, 32), CLAW_TIP: (192, 96, 32, 32)}
FIT_TILES = {EYE}        # mapped whole (the bar pupil must stay visible)
ATLAS, DENSITY = 256, 4
rng = random.Random(42)  # uv offsets
prng = random.Random(7)  # feeler phases
SIDES = ((1, "_l"), (-1, "_r"))

def V(*p):
    return Vector(p)

def mir(p, s):
    return Vector((p[0] * s, p[1], p[2]))

def Q(rot):
    return Euler(tuple(math.radians(a) for a in rot), "XYZ").to_quaternion()

# --- skeleton (armature space) --------------------------------------------------
BONES = {}  # name: (head, tail, parent); every tail is head + 1.5 Y (see the header)

def bone(name, head, parent=None):
    head = Vector(head)
    BONES[name] = (head, head + V(0, 1.5, 0), parent)

bone("root", (0, 0, 0))
bone("hips", (0, 0, 6.0), "root")
bone("spine1", (0, 0.3, 8.0), "hips")      # belly
bone("spine2", (0, 0.8, 11.2), "spine1")   # chest, shoulders, wing roots
bone("neck", (0, 2.2, 13.2), "spine2")
N = V(0, 4.0, 12.6)                         # head joint: in front of the chest, below the hump
HEAD_PITCH = 30                             # the head hangs forward, nose down
HQ = Q((-HEAD_PITCH, 0, 0))
def H(x, y, z):
    """Head-frame point (origin N, before the rest pitch) -> armature space."""
    return N + HQ @ V(x, y, z)
bone("head", N, "neck")
bone("mantle", H(0, -0.6, 3.4), "head")    # back of the dome: pulses when breathing

# Feelers: 8 chains of 3, two rows on the lower face. 1-5 front row from +X to -X,
# 6-8 back row from +X to -X. They hang straight down and splay a little.
FEELERS = {}  # k: [P0, P1, P2, P3], widths
F_ROOTS = [(2.0, 4.6, 0.3), (1.0, 4.8, 0.1), (0.0, 4.9, 0.0), (-1.0, 4.8, 0.1), (-2.0, 4.6, 0.3),
           (1.5, 3.6, -0.5), (0.0, 3.8, -0.6), (-1.5, 3.6, -0.5)]
F_LEN = [0.92, 1.02, 1.08, 1.02, 0.92, 0.86, 0.94, 0.86]
for k, (x, y, z) in enumerate(F_ROOTS, 1):
    p0 = H(x, y, z)
    d = V(0.14 * x, 0.06, -1).normalized()
    pts = [p0]
    for L in (2.6, 2.4, 2.2):
        pts.append(pts[-1] + d * L * F_LEN[k - 1])
    w = (1.1, 0.82, 0.55) if k <= 5 else (1.0, 0.74, 0.5)
    FEELERS[k] = (pts, w)
    for i, c in enumerate("abc"):
        bone(f"feeler{k}{c}", pts[i], "head" if i == 0 else f"feeler{k}{'abc'[i - 1]}")

ARM, LEG, WINGP, WING_MID = {}, {}, {}, {}
for s, sfx in SIDES:
    # arms: gorilla-long, hanging with a bent elbow, claw tips at knee height
    S, E, W, C = mir((4.5, 1.0, 12.6), s), mir((6.1, 0.6, 9.0), s), mir((6.0, 3.2, 6.4), s), mir((5.8, 5.4, 5.3), s)
    ARM[s] = (S, E, W, C)
    bone("uarm" + sfx, S, "spine2")
    bone("farm" + sfx, E, "uarm" + sfx)
    bone("hand" + sfx, W, "farm" + sfx)
    bone("claws" + sfx, C, "hand" + sfx)
    # legs hang from root (not hips) so the hip sway doesn't push the feet into the ground
    Hp, K, A, T = mir((2.7, 0, 6.0), s), mir((3.6, 2.2, 3.4), s), mir((3.3, -0.2, 1.2), s), mir((3.3, 3.4, 0.5), s)
    LEG[s] = (Hp, K, A, T)
    bone("thigh" + sfx, Hp, "root")
    bone("shin" + sfx, K, "thigh" + sfx)
    bone("foot" + sfx, A, "shin" + sfx)
    # wings: spar from the shoulder hump back and up, arching forward to the hook (wing_X1),
    # blade from the hook down the back almost to the ground (wing_X2)
    R0, WM, HK, BT = mir((2.2, -2.6, 14.4), s), mir((3.6, -4.5, 18.5), s), mir((3.9, -3.3, 21.0), s), mir((4.2, -5.8, 6.4), s)
    WINGP[s] = (R0, HK, BT)
    WING_MID[s] = WM
    bone(f"wing{sfx}1", R0, "spine2")
    bone(f"wing{sfx}2", HK, f"wing{sfx}1")

# --- geometry ---------------------------------------------------------------------
boxes = []  # (center, size, quat, bone, tile, {face: tile}, only, plate_flip or None)

def box(c, s, b, tile=SKIN, rot=(0, 0, 0), frame=None, **faces):
    """frame: rotation applied to the centre (about N) and the box (head-frame boxes)."""
    q = Q(rot)
    c = Vector(c)
    if frame is not None:
        c, q = N + frame @ c, frame @ q
    boxes.append((c, tuple(s), q, b, tile, faces, None, None))

def hbox(c, s, b="head", tile=SKIN, rot=(0, 0, 0), **faces):
    box(c, s, b, tile, rot, frame=HQ, **faces)

def dome(c, r, b, tile=SKIN, slabs=((-1, 1, 1),), frame=None, **faces):
    """Blocky ellipsoid, centre c, radii r: per slab (z0, z1, f; z in radii, f = how wide the
    slab is) three boxes whose plan is a rounded cross, so no view shows a square corner."""
    for z0, z1, f in slabs:
        for kx, ky in ((1, 0.56), (0.56, 1), (0.84, 0.84)):
            box((c[0], c[1], c[2] + r[2] * (z0 + z1) / 2), (2 * r[0] * f * kx, 2 * r[1] * f * ky, r[2] * (z1 - z0)),
                b, tile, frame=frame, **faces)

def seg(p0, p1, w, h, b, tile=SKIN, ext=0.3, up=V(0, 0, 1), **faces):
    """Box running from p0 to p1 (local Y), w wide (local X), h thick (local Z, towards up)."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    y = d.normalized()
    x = y.cross(up).normalized()
    q = Matrix((x, y, x.cross(y))).transposed().to_quaternion()
    boxes.append(((p0 + p1) / 2, (w, d.length + 2 * ext, h), q, b, tile, faces, None, None))

def plate(origin, along, across, length, width, b, tile):
    """Thin alpha-textured plate: starts at origin, runs `length` along `along` and `width`
    along `across`. Only the two big faces are emitted. Tile x = along, tile y = across."""
    y = Vector(along).normalized()
    a = Vector(across).normalized()
    a = (a - y * a.dot(y)).normalized()
    flip = a.cross(y).z < 0
    x = -a if flip else a
    q = Matrix((x, y, x.cross(y))).transposed().to_quaternion()
    c = Vector(origin) + y * length / 2 + a * width / 2
    boxes.append((c, (width, length, 0.06), q, b, tile, {}, ("top", "bottom"), flip))

# Legs: thick bent thighs, short shins, long flat feet with three long talons and a spur
for s, sfx in SIDES:
    Hp, K, A, T = LEG[s]
    seg(Hp + V(0, 0, 0.8), K, 3.8, 3.8, "thigh" + sfx)
    box(K + V(0, 0.2, 0), (3.1, 3.0, 3.0), "thigh" + sfx, SKIN_DARK)
    seg(K, A + V(0, 0, 0.5), 2.9, 2.9, "shin" + sfx, ext=0.2)
    box(A + V(0, 0, 0.3), (2.9, 2.4, 1.8), "foot" + sfx, SKIN_DARK)
    box((A.x, 1.5, 0.6), (3.3, 4.2, 1.2), "foot" + sfx, SKIN_DARK)
    box((A.x, -1.5, 0.45), (0.6, 1.2, 0.6), "foot" + sfx, CLAW, rot=(-20, 0, 0))   # spur
    for dx in (-1.05, 0, 1.05):
        box((A.x + dx, 4.2, 0.6), (0.8, 1.8, 0.9), "foot" + sfx, CLAW)
        box((A.x + dx * 1.15, 5.6, 0.52), (0.55, 1.6, 0.55), "foot" + sfx, CLAW_TIP, rot=(-18, 0, 0))

# Torso: the pear. Pelvis, a bloated belly (widest, low), a narrower chest leaning forward
# with shoulder masses and a high hump between the wing roots. Pale belly bands in front,
# scale ridges down the back.
box((0, 0.0, 6.5), (7.8, 6.8, 2.8), "hips", bottom=BELLY)
dome((0, 0.9, 8.6), (4.8, 4.5, 2.9), "spine1", slabs=((-1, -0.5, 0.8), (-0.5, 0.45, 1), (0.45, 0.9, 0.84)), front=BELLY)
for z, w, y in ((7.5, 4.4, 5.45), (8.6, 4.8, 5.5), (9.7, 4.4, 5.45), (10.75, 3.6, 4.75)):
    box((0, y, z), (w, 0.4, 0.75), "spine1", BELLY)
box((0, 1.1, 12.3), (7.6, 6.2, 3.2), "spine2", rot=(-14, 0, 0), front=BELLY)
box((0, 1.9, 13.9), (6.2, 4.6, 1.8), "spine2", rot=(-22, 0, 0))
dome((0, -1.5, 14.1), (3.3, 2.5, 2.4), "spine2", SKIN_DARK, slabs=((-1, -0.3, 0.9), (-0.3, 0.5, 1), (0.5, 0.85, 0.8), (0.85, 1, 0.5)))   # hump
for s in (1, -1):
    box((4.1 * s, 0.9, 12.7), (2.8, 3.4, 3.0), "spine2")                 # shoulder
for b, y, z in (("spine2", -4.2, 14.6), ("spine2", -4.1, 13.0), ("spine1", -3.8, 10.8), ("spine1", -3.9, 9.2), ("spine1", -3.6, 7.6)):
    box((0, y, z), (1.4, 0.9, 1.1), b, SKIN_DARK, rot=(-12, 0, 0))                  # scale ridge
box((0, 3.1, 13.0), (5.0, 3.8, 2.6), "neck", rot=(-24, 0, 0))

# Head: a bulbous scaly dome bent forward, with the mantle bulging up and back behind it
# (an octopus head, not a helmet); a narrower face under its front, where the feelers hang
# from a dark hollow; a cluster of three small eyes per side (two in front, one on the side).
HEAD_SLABS = ((-0.95, -0.45, 0.86), (-0.45, 0.45, 1), (0.45, 0.72, 0.88), (0.72, 0.9, 0.68), (0.9, 1, 0.42))
dome((0, 1.4, 3.3), (3.5, 3.6, 3.3), "head", slabs=HEAD_SLABS, frame=HQ)
dome((0, -1.5, 3.7), (2.9, 2.6, 2.6), "mantle", slabs=HEAD_SLABS[1:], frame=HQ)
hbox((0, 3.4, 0.5), (4.6, 3.6, 1.8), bottom=SOCKET)                                  # face
hbox((0, 5.05, 1.5), (3.2, 0.5, 0.5), tile=SKIN_DARK)                                # lip above the feelers
for s in (1, -1):
    hbox((1.15 * s, 5.02, 2.5), (1.15, 0.12, 1.0), tile=EYE)
    hbox((2.35 * s, 4.48, 3.4), (1.15, 0.12, 1.0), tile=EYE)
    hbox((3.0 * s, 3.2, 2.6), (0.12, 1.15, 1.0), tile=EYE)
    hbox((2.5 * s, 2.8, 0.6), (0.6, 2.6, 1.6), tile=SKIN_DARK)                       # cheek

# Feelers: tapering segments
for k, (pts, w) in FEELERS.items():
    for i, c in enumerate("abc"):
        seg(pts[i], pts[i + 1], w[i], w[i], f"feeler{k}{c}", FEELER, ext=0.25, up=V(0, 1, 0))

# Arms: big shoulders, heavy forearms that widen to the wrist, flat hands as big as the
# face, four long hooked claws and a thumb claw
for s, sfx in SIDES:
    S, E, W, C = ARM[s]
    box(S, (3.0, 3.0, 3.0), "uarm" + sfx, SKIN_DARK)
    seg(S, E, 2.7, 2.7, "uarm" + sfx)
    box(E, (2.6, 2.6, 2.6), "farm" + sfx, SKIN_DARK)
    seg(E, W, 2.5, 2.3, "farm" + sfx)
    seg(E + (W - E) * 0.45, W, 3.0, 2.7, "farm" + sfx, ext=0.1)
    seg(W, C, 3.8, 1.5, "hand" + sfx, ext=0.5)
    y = (C - W).normalized()
    x = y.cross(V(0, 0, 1)).normalized()
    z = x.cross(y)
    for dx in (-1.38, -0.46, 0.46, 1.38):
        b0 = C + x * dx + z * 0.05
        b1 = b0 + (y * 0.9 - z * 0.25).normalized() * 1.8
        b2 = b1 + (y * 0.45 - z * 1.0).normalized() * 1.7
        seg(b0, b1, 0.7, 0.62, "claws" + sfx, CLAW, ext=0.2)
        seg(b1, b2, 0.46, 0.44, "claws" + sfx, CLAW_TIP, ext=0.15)
    # thumb claw on the inner side
    t0 = W + (C - W) * 0.5 - x * s * 1.8
    seg(t0, t0 + (y * 0.6 - x * s * 0.3 - z * 0.7).normalized() * 1.8, 0.55, 0.55, "hand" + sfx, CLAW, ext=0.15)

# Wings: arched spar + hook on wing_X1, rib + membrane on wing_X2. The membrane faces
# backwards (two narrow blades seen from behind, as in the back sketch), so spreading them
# by a roll shows the membrane from the front.
for s, sfx in SIDES:
    R0, HK, BT = WINGP[s]
    WM = WING_MID[s]
    w1, w2 = f"wing{sfx}1", f"wing{sfx}2"
    seg(R0, WM, 1.3, 1.3, w1, SKIN_DARK)
    seg(WM, HK, 1.1, 1.1, w1, SKIN_DARK)
    HT = HK + V(-0.1 * s, 1.9, -0.1)
    seg(HK, HT, 0.9, 0.9, w1, SKIN_DARK, ext=0.25)                                   # hook
    seg(HT, HT + V(-0.05 * s, 0.7, -1.3), 0.6, 0.6, w1, CLAW_TIP, ext=0.15)
    seg(HK, BT, 0.7, 0.7, w2, SKIN_DARK, ext=0.2)
    out_back = V(s, -0.35, 0)
    plate(HK + V(0, 0, 0.3), BT - HK, out_back, (BT - HK).length * 1.02, 3.6, w2, WING)
    plate(R0 + (WM - R0) * 0.3, WM - R0, out_back, (WM - R0).length * 0.9, 1.8, w1, WING)

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

me = bpy.data.meshes.new("cthulhu")
me.from_pydata(verts, [], faces)
uv = me.uv_layers.new(name="UVMap")
for poly, fuv in zip(me.polygons, uvs):
    for li, co in zip(poly.loop_indices, fuv):
        uv.data[li].uv = co
bm = bmesh.new(); bm.from_mesh(me)
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bm.to_mesh(me); bm.free()
me.update()

obj = bpy.data.objects.new("cthulhu", me)
scn.collection.objects.link(obj)
me.materials.append(bpy.data.materials.new("cthulhu"))

# --- armature -------------------------------------------------------------------------
arm_data = bpy.data.armatures.new("Armature")
arm = bpy.data.objects.new("Armature", arm_data)
scn.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
for name, (h, t, _) in BONES.items():
    eb = arm_data.edit_bones.new(name); eb.head, eb.tail = h, t
    eb.roll = 0   # along +Y, roll 0: local axes == model axes
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
#   X = pitch: + lifts what lies ahead (+Y) of the pivot and swings a hanging limb forward.
#   Y = roll:  + moves the +X side down; a hanging limb swings towards -X.
#   Z = yaw:   + turns +X towards +Y, i.e. the nose swings towards the -X (_r) side.
# loc = offset in armature units, scl = per-bone scale (only on bones without children).
for pb in arm.pose.bones:
    pb.rotation_mode = "QUATERNION"

def R(axis, deg):
    return Quaternion({"X": (1, 0, 0), "Y": (0, 1, 0), "Z": (0, 0, 1)}[axis], math.radians(deg))

def key(frame, loc=None, scl=None, **rots):
    loc, scl = loc or {}, scl or {}
    for name in BONES:
        pb = arm.pose.bones[name]
        rest = pb.bone.matrix_local.to_quaternion()
        r = rots.get(name, (0, 0, 0))
        q = r if isinstance(r, Quaternion) else Q(r)
        pb.rotation_quaternion = rest.inverted() @ q @ rest
        pb.location = rest.inverted() @ Vector(loc.get(name, (0, 0, 0)))
        pb.scale = Vector(scl.get(name, (1, 1, 1)))
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        pb.keyframe_insert("location", frame=frame)
        pb.keyframe_insert("scale", frame=frame)

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
    """l for the _l bone, r for the _r one; r defaults to l mirrored (roll and yaw negated)."""
    if r is None:
        r = (l[0], -l[1], -l[2])
    return {prefix + "_l": l, prefix + "_r": r}

def side(prefix, s, v):
    return {prefix + ("_l" if s > 0 else "_r"): v}

PHASE = [prng.uniform(0, TAU) for _ in range(9)]

def feelers(fn):
    """fn(k, i, x) -> (pitch, roll, yaw) for feeler k (1..8), segment i (0..2); x is the
    root's sideways position in the head frame (+ = _l side)."""
    d = {}
    for k in range(1, 9):
        for i, c in enumerate("abc"):
            d[f"feeler{k}{c}"] = fn(k, i, F_ROOTS[k - 1][0])
    return d

def writhe(t, amp=10.0, lag=0.0, speed=1):
    """Waves running down every feeler; t in radians of the clip's base cycle."""
    return feelers(lambda k, i, x: (amp * (i + 1) / 3 * sin(2 * speed * t + PHASE[k] - i * 0.9 - lag),
                                    0.6 * amp * (i + 1) / 3 * sin(3 * speed * t + 1.3 * PHASE[k] - i * 0.9 - lag), 0))

def frame_q(b, a):
    """Rotation of the frame (b, a orthogonalised, b x a) relative to the model axes."""
    b = Vector(b).normalized()
    a = (Vector(a) - b * Vector(a).dot(b)).normalized()
    return Matrix((b, a, b.cross(a))).transposed().to_quaternion()

# Fully spread wing (roar): the spar rolls outwards, the blade points out and a little
# down from the hook with the membrane hanging below it towards the body (a bat's wing),
# so the membrane faces forwards. q2 is relative to wing_X1's posed frame.
WING_OPEN = {}
for s, sfx in SIDES:
    R0, HK, BT = WINGP[s]
    q1 = R("Y", s * 42) @ R("X", -8)
    t2 = frame_q(V(s * 0.85, -0.25, -0.45), V(-s * 0.4, -0.1, -0.9)) @ frame_q(BT - HK, V(s, -0.35, 0)).inverted()
    WING_OPEN[s] = (q1, q1.inverted() @ t2)

def wings(open=0.0, twitch=0.0, back=0.0):
    """open: 0 = folded (the rest pose), 1 = fully spread; back: pitch of the whole wing
    (+ = the hook leans forward over the head); twitch is added to back."""
    d = {}
    for s, sfx in SIDES:
        q1, q2 = WING_OPEN[s]
        d[f"wing{sfx}1"] = Quaternion().slerp(q1, open) @ Q((back + twitch, 0, 0)) if open else (back + twitch, 0, 0)
        d[f"wing{sfx}2"] = Quaternion().slerp(q2, open)
    return d

def legs(thigh, shin, toe=0.0):
    """Both legs bent by the same angles, soles kept flat (+ toe). Returns the pose and how
    far the soles rise, i.e. how far root has to drop to keep them on the ground."""
    Hp, K, A, _ = LEG[1]
    def rz(v, deg):
        return v.y * sin(math.radians(deg)) + v.z * cos(math.radians(deg))
    lift = rz(K - Hp, thigh) + rz(A - K, thigh + shin) - (A - Hp).z
    pose = dict(**both("thigh", (thigh, 0, 0)), **both("shin", (shin, 0, 0)), **both("foot", (-(thigh + shin) + toe, 0, 0)))
    return pose, lift

def stand_pose(t):
    """The idle pose at phase t (one cycle = 2 pi); t = 0 is the neutral pose every one-shot
    clip starts and ends in."""
    br = sin(t)
    p = writhe(t)
    p.update(wings(twitch=1.2 * sin(2 * t + 1)))
    p["spine1"] = (0.8 * br, 0, 0)
    p["spine2"] = (1.2 * br, 0, 0)
    p["neck"] = (-1.0 * br, 0, 0.8 * sin(t + 1))
    p["head"] = (-1.5 * sin(t - 1.2), 0, 1.5 * sin(t + 0.4))
    p.update(both("uarm", (2 * br, 0, 0)))
    p.update(both("farm", (-2 * br, 0, 0)))
    p.update(both("claws", (6 * sin(2 * t), 0, 0), (6 * sin(2 * t + 2), 0, 0)))
    return p

def stand_scl(t):
    m = 1 + 0.07 * sin(t - 0.6)
    return {"mantle": (m, m, m)}

NEUTRAL = stand_pose(0)
NEUTRAL_SCL = stand_scl(0)

def P(**over):
    return dict(NEUTRAL, **over)

def keyn(frame, loc=None, **over):
    key(frame, loc=loc, scl=NEUTRAL_SCL, **P(**over))

# stand 0-60
for f in range(0, 61, 2):
    key(f, scl=stand_scl(TAU * f / 60), **stand_pose(TAU * f / 60))

# walk 70-110: one full stride cycle (left + right step), same scheme as gojira's walk.
# Stance: the sole moves backwards at constant speed and root drops by however much the
# ankle's arc lifts the sole (plants the foot, gives the bob). Swing: eased return, knee high.
# "A mountain walked or stumbled": he leans forward, throws his weight over the stance foot
# (hips shift and roll, bigger on the right step: the stumble), the chest counter-rolls, the
# long arms swing against the legs with the forearms lagging, the head nods on every step and
# the feelers swing after it like a pendulum.
A_STRIDE = 20
LEG_V = LEG[1][2] - LEG[1][0]                           # hip -> ankle at rest
LEG_R = math.hypot(LEG_V.y, LEG_V.z)
LEG_PHI = math.degrees(math.atan2(-LEG_V.y, -LEG_V.z))  # thigh angle that puts the ankle under the hip
WALK_CYCLE_UNITS = 2 * 2 * LEG_R * sin(math.radians(A_STRIDE))
for f in range(70, 111):
    ph = TAU * (f - 70) / 40
    pose = writhe(ph, amp=10, lag=0.8)
    for name, (px, py, pz) in list(pose.items()):       # pendulum: the beard swings fore and aft
        i = "abc".index(name[-1])
        pose[name] = (px + (12 if i == 0 else 4) + (9 if i == 0 else 7) * cos(2 * ph - 1.9 - 0.7 * i), py, pz)
    drop = 0.0
    for s, sfx, off in ((1, "_l", 0), (-1, "_r", math.pi)):
        p = (ph + off) % TAU
        if p <= math.pi + 1e-9:                 # stance
            swing = 0.0
            rel = math.degrees(math.asin(sin(math.radians(A_STRIDE)) * (1 - 2 * p / math.pi)))
            drop = max(drop, -LEG_V.z - LEG_R * cos(math.radians(rel)))
        else:
            swing = -sin(p)                     # 0 at lift-off/landing, 1 mid-swing
            rel = A_STRIDE * cos(p)
        thigh = LEG_PHI + rel + 24 * swing
        shin = -58 * swing
        pose["thigh" + sfx] = (thigh, 0, -s * 5 * swing)
        pose["shin" + sfx] = (shin, 0, 0)
        pose["foot" + sfx] = (-(thigh + shin) + 14 * swing, 0, 0)
        # the arm swings forward with the opposite leg; the forearm and claws follow late
        a = ph + off
        pose["uarm" + sfx] = (-18 * cos(a) + 4, -s * (5 + 3 * sin(a)), 0)
        pose["farm" + sfx] = (-10 - 12 * cos(a - 0.9), 0, 0)
        pose["hand" + sfx] = (8 * cos(a - 1.6), 0, 0)
        pose["claws" + sfx] = (10 * cos(a - 2.2), 0, 0)
    lurch = sin(ph) * (1.5 if sin(ph) < 0 else 1.0)      # + = weight on the _l foot
    roll = 7 * lurch
    pose["hips"] = (-5 + 2 * cos(2 * ph), roll, 6 * cos(ph))
    pose["spine1"] = (-2, -0.5 * roll, -3 * cos(ph))
    pose["spine2"] = (-3 + 2.5 * cos(2 * ph - 0.5), -0.6 * roll, -5 * cos(ph))
    pose["neck"] = (4 * cos(2 * ph - 0.9), 0.3 * roll, 2 * cos(ph))
    pose["head"] = (4 - 6 * cos(2 * ph - 1.5), 0.5 * roll, 4 * cos(ph - 0.4))
    pose.update(wings(twitch=3.5 * cos(2 * ph - 1.2), back=-2))
    for s, sfx in SIDES:                                 # the folded wings sway with the lurch
        pose[f"wing{sfx}2"] = (0, 2.5 * lurch, 0)
    key(f, loc={"root": (0, 0, -drop), "hips": (0.7 * lurch, 0, -0.25 * (1 - cos(2 * ph)) / 2)}, scl=stand_scl(2 * ph), **pose)

# swim 120-160: body pitched 70 deg forward, head up, big alternating overarm strokes,
# frog-ish leg kicks, wings flat on the back, feelers streaming backwards.
SWIM_PITCH = -70
SWIM_CENTRE = V(0, 0.4, 9.0)            # the belly; it stays at SWIM_AT above the origin
SWIM_AT = V(0, 0, 4.5)
for f in range(120, 161):
    ph = TAU * (f - 120) / 40
    rq = Q((SWIM_PITCH + 3 * sin(2 * ph), 0, 2 * sin(ph)))
    loc = SWIM_AT - rq @ SWIM_CENTRE + V(0, 0, 0.4 * sin(2 * ph))
    pose = {"root": rq, "spine1": (2 * sin(2 * ph), 0, 0), "spine2": (0, 4 * sin(ph), 3 * sin(ph))}
    pose["neck"] = (32, 0, -2 * sin(ph))
    pose["head"] = (30, 0, -3 * sin(ph))
    pose.update(feelers(lambda k, i, x: (-55 if i == 0 else 8 * sin(2 * ph + PHASE[k] - i * 1.2),
                                         -x * 6 + 6 * sin(2 * ph + PHASE[k] - i), 0)))
    for s, sfx, off in ((1, "_l", 0), (-1, "_r", math.pi)):
        a = ((ph + off) % TAU) / TAU           # 0..1 through one stroke
        # overarm: the arm swings forward over the head (recovery, elbow bent), then pulls
        # straight down and back along the body
        sweep = 360 * a                        # pitch, continuous through the cycle
        bend = -45 * max(0, sin(TAU * a - math.pi)) if a > 0.5 else -10
        pose["uarm" + sfx] = R("X", -sweep + 160) @ R("Y", -s * 18)
        pose["farm" + sfx] = (bend, 0, 0)
        pose["hand" + sfx] = (10, 0, 0)
        pose["claws" + sfx] = (-10 if a < 0.5 else 25, 0, 0)
        k = sin(2 * ph + off)
        pose["thigh" + sfx] = (10 + 22 * k, 0, -s * 6)
        pose["shin" + sfx] = (-30 - 25 * max(0, -k), 0, 0)
        pose["foot" + sfx] = (-40, 0, 0)
    pose.update(wings(back=-12, twitch=2 * sin(2 * ph)))
    key(f, loc={"root": tuple(loc)}, scl=NEUTRAL_SCL, **pose)

# dormant (the idol pose, see below) and rise share the squat
SQUAT, SQUAT_LIFT = legs(45, -28)

def dormant_pose(t):
    p = dict(SQUAT)
    p["root"] = (0, 0, 0)
    p["hips"] = (0, 0, 0)
    p["spine1"] = (-4, 0, 0)
    p["spine2"] = (-8, 0, 0)
    p["neck"] = (-6, 0, 0)
    p["head"] = (-10 + 1.5 * sin(t), 0, 1.0 * sin(t + 1))
    # upper arms hang, forearms lie level on the knees, the hands hang over them
    p.update(both("uarm", (16, 4, 0)))
    p.update(both("farm", (32, 0, 0)))
    p.update(both("hand", (-62, 0, 0)))
    p.update(both("claws", (-22, 0, 0)))
    p.update(wings(back=10, twitch=0.8 * sin(t)))
    # the beard hangs plumb from the bowed face (28 = the bow) and curls forward over the
    # hands, well clear of the ground (asserted in the self-check)
    p.update(feelers(lambda k, i, x: ((40, 44, 24)[i] + 4 * (i + 1) / 3 * sin(t + PHASE[k] - i * 0.8), -x * 2 + 3 * (i + 1) / 3 * sin(t + 1.3 * PHASE[k] - i * 0.8), 0)))
    return p

DORMANT_LOC = {"root": (0, 0, -SQUAT_LIFT)}

# rise 170-230: from the idol pose he lifts his head, pushes up from the knees and stands;
# near the end the feelers splay and the wings half open, then settle into "stand".
def splay(amount, shiver=0.0, f=0):
    """Feelers splayed radially (amount 1 = fully), with an optional shiver."""
    return feelers(lambda k, i, x: (amount * (38 if k <= 5 else 25) * (1 if i == 0 else 0.35) + shiver * sin(f * 2.3 + PHASE[k] * 3 + i),
                                    -x * amount * (18 if i == 0 else 6) + shiver * 0.8 * sin(f * 1.9 + PHASE[k] * 5 + i), 0))

D0 = dormant_pose(0)
key(170, loc=DORMANT_LOC, scl=NEUTRAL_SCL, **D0)
key(180, loc=DORMANT_LOC, scl=NEUTRAL_SCL, **dict(D0, neck=(0, 0, 0), head=(14, 0, 0), spine2=(-8, 0, 0),
                                                **feelers(lambda k, i, x: (8 * (i + 1) / 3, -x * 3, 0))))
half, half_lift = legs(22, -14)
key(196, loc={"root": (0, 0, -half_lift)}, scl=NEUTRAL_SCL,
    **dict(D0, **half, spine1=(-14, 0, 0), spine2=(-10, 0, 0), neck=(0, 0, 0), head=(4, 0, 0),
           **both("uarm", (38, -4, 0)), **both("farm", (-20, 0, 0)), **both("hand", (-35, 0, 0)), **both("claws", (-15, 0, 0)),
           **feelers(lambda k, i, x: (12 * (i + 1) / 3, -x * 3, 0))))
key(210, scl=NEUTRAL_SCL, **P(spine1=(-4, 0, 0), spine2=(-4, 0, 0), head=(6, 0, 0), **writhe(1.0, amp=8)))
key(220, scl={"mantle": (1.15, 1.15, 1.15)}, **P(spine1=(3, 0, 0), spine2=(5, 0, 0), neck=(4, 0, 0), head=(10, 0, 0),
                                              **both("uarm", (12, -22, 0)), **both("farm", (-18, 0, 0)), **both("claws", (25, 0, 0)),
                                              **wings(open=0.35), **splay(0.9)))
keyn(230)

# punch 240-260: claw swipe with the _l arm. The body twists, the claws open on the
# wind-up and close at the hit. The hit comes early (243-245), because mcl_mobs deals
# the damage when the clip starts.
keyn(240)
keyn(242, spine1=(2, 0, -6), spine2=(4, 0, -12), head=(4, 0, 6),
     uarm_l=(95, -40, 15), farm_l=(-35, 0, 0), hand_l=(25, 0, 0), claws_l=(35, 0, 0),
     uarm_r=(10, 6, 0))
keyn(245, spine1=(-3, 0, 8), spine2=(-8, 0, 16), head=(-6, 0, -6),
     uarm_l=(70, 25, 25), farm_l=(-15, 0, 0), hand_l=(-10, 0, 0), claws_l=(-40, 0, 0),
     uarm_r=(-10, 8, 0), **splay(0.4))
keyn(249, spine1=(-3, 0, 10), spine2=(-8, 0, 18), head=(-6, 0, -8),
     uarm_l=(35, 40, 20), farm_l=(-20, 0, 0), hand_l=(-15, 0, 0), claws_l=(-45, 0, 0),
     uarm_r=(-8, 8, 0), **splay(0.2))
keyn(260)

# grab 270-300: the _r arm reaches out, the claws open, close on the victim (282) and
# pull it in to the face (hold pose at 290), feelers reaching for it; back to neutral at 300.
# The grip point is printed below (GRIP_OFS on claws_r).
keyn(270)
keyn(277, spine1=(-4, 0, 0), spine2=(-10, 0, 5), neck=(4, 0, 0), head=(6, 0, -4),
     uarm_r=(88, -8, -6), farm_r=(2, 0, 0), hand_r=(10, 0, 0), claws_r=(40, 0, 0),
     uarm_l=(8, 0, 0), **splay(0.5))
keyn(282, spine1=(-4, 0, 0), spine2=(-10, 0, 5), neck=(4, 0, 0), head=(6, 0, -4),
     uarm_r=(84, -8, -6), farm_r=(0, 0, 0), hand_r=(4, 0, 0), claws_r=(-62, 0, 0),
     uarm_l=(8, 0, 0), **splay(0.3))
HOLD = dict(spine1=(-2, 0, 0), spine2=(-4, 0, 2), neck=(-4, 0, 0), head=(-10, 0, -3),
            uarm_r=(38, -6, -36), farm_r=(30, 0, 0), hand_r=(-10, 0, 0), claws_r=(-62, 0, 0),
            uarm_l=(4, 0, 0),
            **feelers(lambda k, i, x: (24 + 10 * i, -x * 2 + (5 if x < 0 else 0), 0)))
keyn(290, **HOLD)
keyn(300)

# roar 310-350, the madness roar: he ducks (314), then rears back with braced knees, throws
# the head up so the whole beard splays radially and shivers, the claws go up and out, wide
# open, the wings spread fully (the only clip where they do) and beat, the mantle swells.
brace, brace_lift = legs(13, -10)
duck, duck_lift = legs(20, -14)
keyn(310)
key(314, loc={"root": (0, 0, -duck_lift)}, scl=NEUTRAL_SCL,
    **P(**duck, spine1=(-6, 0, 0), spine2=(-10, 0, 0), neck=(-4, 0, 0), head=(-12, 0, 0),
        **both("uarm", (-12, -10, 0)), **both("farm", (25, 0, 0)), **both("claws", (-30, 0, 0)),
        **wings(open=0.15, back=-6)))
for f in range(319, 346, 2):
    sh = sin(f * 2.3)
    m = 1.16 + 0.08 * sin(f * 1.3)
    key(f, loc={"root": (0, 0, -brace_lift)}, scl={"mantle": (m, m, m)},
        **P(**brace, hips=(3, 0, 1.5 * sh), spine1=(9, 0, 0), spine2=(15, 1.5 * sh, 0), neck=(12, 0, 0),
            head=(30 + 3 * sin(f * 1.7), 0, 4 * sin(f * 1.1)),
            **both("uarm", (38 + 3 * sh, -72, 0)), **both("farm", (-62, 0, 0)), **both("hand", (18, 0, 0)),
            **both("claws", (42 + 6 * sin(f * 1.9), 0, 0)),
            **wings(open=1.0, twitch=5 * sin(f * 1.3)), **splay(1.25, shiver=9, f=f)))
keyn(350)

# die 360-400: he staggers, sags to his knees, falls forward onto his face and collapses
# (the mantle deflates) to sell "bursting like a bladder"; the Lua spawns the green cloud.
# Root drops so the folded legs keep the soles on the ground; the forward fall pivots on
# the knees; root is then raised until the lowest vertex touches the ground (two passes).
kneel, kneel_lift = legs(20, -63, toe=-25)
def die_keys(lift392, lift400):
    keyn(360)
    keyn(366, spine1=(6, 0, 0), spine2=(10, 0, 0), neck=(8, 0, 0), head=(16, 0, 0),
         **both("uarm", (20, -30, 0)), **wings(open=0.3), **splay(0.8, shiver=5, f=366))
    key(376, loc={"root": (0, 0, -kneel_lift)}, scl=NEUTRAL_SCL,
        **P(**kneel, spine1=(-8, 0, 0), spine2=(-12, 0, 0), neck=(-6, 0, 0), head=(-12, 0, 0),
            **both("uarm", (10, -8, 0)), **both("farm", (-10, 0, 0)), **wings(open=0.1),
            **feelers(lambda k, i, x: (-6, 0, 0))))
    lying = dict(NEUTRAL, **both("thigh", (-8, 0, 0)), **both("shin", (14, 0, 0)), **both("foot", (-70, 0, 0)))
    lying.update(spine1=(-6, 0, 0), spine2=(-6, 0, 0), neck=(35, 0, 0), head=(45, 0, 10))
    lying.update(both("uarm", (150, -40, 0)), **both("farm", (-30, 0, 0)), **both("hand", (20, 0, 0)), **both("claws", (30, 0, 0)))
    lying.update(wings(back=16))
    lying.update(feelers(lambda k, i, x: (105 if i == 0 else -6, -x * 16, 0)))
    key(392, loc={"root": (0, -7, lift392)}, scl={"mantle": (0.8, 0.8, 0.8)}, root=(-80, 0, 0), **{k: v for k, v in lying.items() if k != "root"})
    key(400, loc={"root": (0, -9, lift400)}, scl={"mantle": (0.55, 0.55, 0.55)}, root=(-90, 0, 0), **{k: v for k, v in lying.items() if k != "root"})

def posed(frame):
    scn.frame_set(frame)
    dg = bpy.context.evaluated_depsgraph_get()
    return [v.co.copy() for v in obj.evaluated_get(dg).data.vertices]

# dormant 410-450: the idol pose (squatting on his heels, forearms on the knees, head bent
# so the feeler tips brush the backs of the hands, wings folded with the hooks above the
# head). Only the feelers drift, the mantle breathes slowly.
def dormant_keys():
    for f in range(410, 451, 4):
        t = TAU * (f - 410) / 40
        m = 1 + 0.05 * sin(t)
        key(f, loc=DORMANT_LOC, scl={"mantle": (m, m, m)}, **dormant_pose(t))

die_keys(0, 0)
dormant_keys()
DIE_LIFT = [-min(v.z for v in posed(f)) for f in (392, 400)]
die_keys(*DIE_LIFT)

scn.frame_start, scn.frame_end = 0, 450
arm.animation_data.action.name = "cthulhu"

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

# --- self-check, and the numbers the mob code needs ----------------------------------------
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
    assert (arm_data.bones[name].matrix_local.to_quaternion().rotation_difference(Quaternion())).angle < 1e-4, name + " not along +Y / roll 0"
print("bones:", " ".join(BONES))

def extent(vs):
    xs, ys, zs = [v.x for v in vs], [v.y for v in vs], [v.z for v in vs]
    return min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)

print("SCALE %.1f: 1 unit = %.2f node" % (SCALE, UNIT))
for label, f in (("stand", 0), ("stand", 30), ("dormant", 410), ("roar hold", 330), ("swim", 120), ("die end", 400)):
    x0, x1, y0, y1, z0, z1 = extent(posed(f))
    print("%-9s f%-3d: height %.2f units (%.2f nodes), lowest %.2f; x %.1f..%.1f (%.1f..%.1f nodes), y %.1f..%.1f (%.1f..%.1f nodes)"
          % (label, f, z1, z1 * UNIT, z0, x0, x1, x0 * UNIT, x1 * UNIT, y0, y1, y0 * UNIT, y1 * UNIT))
walk_min = []
for f in range(70, 111, 5):
    vs = posed(f)
    i = min(range(len(vs)), key=lambda i: vs[i].z)
    walk_min.append(vs[i].z)
    if abs(vs[i].z) >= 0.2:
        print("walk f%d: lowest vertex %.2f (%s)" % (f, vs[i].z, vert_bone[i]))
print("WALK_CYCLE_UNITS %.3f (%.2f nodes); lowest vertex per walk frame: %s"
      % (WALK_CYCLE_UNITS, WALK_CYCLE_UNITS * UNIT, " ".join("%.2f" % z for z in walk_min)))
assert all(abs(z) < 0.2 for z in walk_min), "walk: stance foot not on the ground"
for f in (410, 430):
    vs = posed(f)
    i = min(range(len(vs)), key=lambda i: vs[i].z)
    print("dormant f%d lowest vertex %.2f (%s)" % (f, vs[i].z, vert_bone[i]))
dorm_min = min(v.z for f in range(410, 451, 2) for v in posed(f))
assert dorm_min > -0.06, "dormant: something dips into the ground (%.2f)" % dorm_min
print("die root lift: frame 392 %.2f, frame 400 %.2f" % tuple(DIE_LIFT))

# Bone-space points the mob code needs: (forward, side towards +X/_l, up) in units and nodes,
# for kaiju_core.model_point(self, fwd, side, up).
GRIP_OFS = V(0, 1.9, -1.2)    # between the closed claws, relative to the claws_r joint at rest
def bone_point(name, rest_point, frame):
    scn.frame_set(frame)
    bpy.context.view_layer.update()
    pb = arm.pose.bones[name]
    return pb.matrix @ pb.bone.matrix_local.inverted() @ rest_point

def report(label, name, rest_point, frames):
    for f in frames:
        p = bone_point(name, rest_point, f)
        print("%-10s f%-3d %-8s: forward %6.2f, side %6.2f, up %6.2f units = (%.2f, %.2f, %.2f) nodes"
              % (label, f, name, p.y, p.x, p.z, p.y * UNIT, p.x * UNIT, p.z * UNIT))

C_R = ARM[-1][3]
report("grip", "claws_r", C_R + GRIP_OFS, (0, 277, 282, 290))
report("head", "head", N, (0, 330, 410))
report("face", "head", H(0, 5.0, 1.0), (0, 290, 330))
print("grip point rest offset from the claws_r joint (Blender x, y, z units):", tuple(GRIP_OFS),
      "-> Luanti bone-local {x=%.1f, y=%.1f, z=%.1f}" % (GRIP_OFS.x, GRIP_OFS.z, GRIP_OFS.y))
