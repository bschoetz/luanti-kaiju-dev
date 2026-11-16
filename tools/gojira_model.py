# Builds kaiju/gojira/models/gojira.glb (blocky skinned + animated kaiju).
#   blender -b --factory-startup --python tools/gojira_model.py -- kaiju/gojira/models/gojira.glb
# Conventions (Luanti 5.17 glTF loader):
#   * Blender Z-up, model faces Blender +Y (= entity forward in Luanti).
#   * 10 units = 1 node at visual_size 1; the mob uses visual_size 7.5, so 1 unit = 0.75 node.
#   * scene fps = 1 -> glTF time in seconds == Blender frame, so Lua can use b3d-style
#     frame ranges (animation.walk_start etc.) with any playback speed.
#   * Texture atlas gojira.png: 256x256, 4x4 tiles of 64px, see tools/gojira_texture.py.
#     Faces get texels at a fixed density (DENSITY px per unit) so detail doesn't stretch.
#   * Rigid skinning: every box belongs 100% to one bone; boxes overlap at joints.
import bpy, bmesh, sys, math, random
from mathutils import Euler, Vector

out = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)
scn = bpy.context.scene
scn.render.fps = 1

# Atlas tiles; keep in sync with gojira_texture.py
(SKIN, SKIN_DARK, BELLY, PLATE, EYE, TOOTH, MOUTH, TONGUE,
 CLAW, BLACK, SOCKET, PLATE_TIP) = range(12)
FIT_TILES = {EYE}      # mapped whole (the slit pupil must stay visible)
ATLAS, TILE, DENSITY = 256, 64, 4
rng = random.Random(42)

# --- skeleton (armature space) --------------------------------------------------
BONES = {}  # name: (head, tail, parent)

def bone(name, head, tail, parent=None):
    BONES[name] = (Vector(head), Vector(tail), parent)

bone("root", (0, 0, 0), (0, 0, 2))
bone("hips", (0, 0, 8.2), (0, 0, 10.2), "root")
bone("spine1", (0, 0.2, 10.2), (0, 0.8, 13.0), "hips")
bone("spine2", (0, 0.8, 13.0), (0, 1.6, 15.8), "spine1")
bone("neck1", (0, 1.6, 15.8), (0, 2.1, 17.3), "spine2")
bone("neck2", (0, 2.1, 17.3), (0, 2.6, 18.4), "neck1")
bone("head", (0, 2.6, 18.4), (0, 6.5, 18.8), "neck2")
bone("jaw", (0, 2.9, 17.7), (0, 7.0, 17.3), "head")

ARM = {}  # side -> joint positions
LEG = {}
for s, sfx in ((1, "_l"), (-1, "_r")):
    S, E = (3.0 * s, 2.2, 15.4), (3.6 * s, 3.2, 13.2)
    W, F = (3.4 * s, 4.8, 12.4), (3.4 * s, 6.0, 12.0)
    ARM[s] = (Vector(S), Vector(E), Vector(W), Vector(F))
    bone("uarm" + sfx, S, E, "spine2")
    bone("farm" + sfx, E, W, "uarm" + sfx)
    bone("hand" + sfx, W, F, "farm" + sfx)
    # legs hang from root (not hips) so the hip bob doesn't push the feet into the ground
    H, K = (2.6 * s, 0, 8.2), (2.75 * s, 1.4, 4.6)
    A, T = (2.75 * s, -0.4, 1.3), (2.75 * s, 3.4, 0.6)
    LEG[s] = (Vector(H), Vector(K), Vector(A), Vector(T))
    bone("thigh" + sfx, H, K, "root")
    bone("shin" + sfx, K, A, "thigh" + sfx)
    bone("foot" + sfx, A, T, "shin" + sfx)

# S-curve: level at the base, drops to drag just above the ground, tip slightly raised.
# gojira/init.lua has a TAIL table derived from these points and widths; keep it in sync.
TAIL_PTS = [Vector(p) for p in [(0, -2.4, 8.6), (0, -5.4, 8.2), (0, -8.4, 7.2), (0, -11.3, 5.6),
                                (0, -14.2, 3.8), (0, -17.0, 2.4), (0, -19.8, 1.6), (0, -22.5, 1.4),
                                (0, -25.0, 1.9)]]
TAIL_W = [4.8, 4.2, 3.6, 3.0, 2.4, 1.9, 1.4, 1.0]
for i in range(8):
    bone(f"tail{i + 1}", TAIL_PTS[i], TAIL_PTS[i + 1], "hips" if i == 0 else f"tail{i}")

# --- geometry ---------------------------------------------------------------------
boxes = []  # (center Vector, size, rotation Quaternion, bone, tile, {face: tile})

def box(c, s, b, tile=SKIN, rot=(0, 0, 0), **faces):
    q = Euler(tuple(math.radians(a) for a in rot), "XYZ").to_quaternion()
    boxes.append((Vector(c), s, q, b, tile, faces))

def seg(p0, p1, w, h, b, tile=SKIN, ext=0.3, **faces):
    """Box running from p0 to p1 (local Y), w wide (local X), h thick (local Z)."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    q = d.normalized().to_track_quat("Y", "Z")
    boxes.append(((p0 + p1) / 2, (w, d.length + 2 * ext, h), q, b, tile, faces))

def plate(base, height, length, b, lean=20, scale=1.0, pitch=0):
    """Dorsal plate: three stacked slabs narrowing to a tip, leaning backwards."""
    h, l = height * scale, length * scale
    q = Euler((math.radians(lean + pitch), 0, 0), "XYZ").to_quaternion()
    up = q @ Vector((0, 0, 1))
    z = 0
    for frac_h, frac_l, tile in ((0.45, 1.0, PLATE), (0.33, 0.68, PLATE), (0.3, 0.36, PLATE_TIP)):
        hh = h * frac_h
        c = Vector(base) + up * (z + hh / 2)
        boxes.append((c, (0.7 * scale + 0.1, l * frac_l, hh), q, b, tile, {}))
        z += hh * 0.92

# Legs
for s, sfx in ((1, "_l"), (-1, "_r")):
    H, K, A, T = LEG[s]
    seg(H + Vector((0, 0, 0.8)), K, 3.8, 4.2, "thigh" + sfx)
    seg(H + Vector((0.3 * s, 0.4, 0.2)), K + Vector((0.3 * s, 0.2, 0.8)), 3.4, 3.6, "thigh" + sfx, SKIN_DARK)  # outer muscle
    box(K + Vector((0, 0.3, 0)), (2.9, 2.6, 2.8), "thigh" + sfx)                                           # knee
    seg(K, A, 2.7, 2.9, "shin" + sfx)
    box(A + Vector((0, 0, 0.1)), (2.8, 2.0, 1.8), "foot" + sfx, SKIN_DARK)                                 # heel
    box((A.x, 1.3, 0.7), (3.6, 4.4, 1.4), "foot" + sfx, SKIN_DARK, bottom=BLACK)                          # foot
    box((A.x - 1.6 * s, -1.4, 0.4), (0.6, 1.0, 0.6), "foot" + sfx, CLAW, rot=(-15, 0, 0))                 # spur
    for dx in (-1.15, 0, 1.15):
        box((A.x + dx, 3.9, 0.55), (0.95, 1.6, 1.0), "foot" + sfx, SKIN_DARK)                             # toe
        box((A.x + dx, 4.95, 0.4), (0.6, 0.9, 0.7), "foot" + sfx, CLAW, rot=(-20, 0, 0))                  # claw

# Torso
box((0, -0.3, 9.2), (6.6, 5.4, 3.6), "hips", bottom=BELLY)
box((0, 0.4, 11.6), (6.8, 5.6, 3.8), "spine1", rot=(-8, 0, 0))
box((0, 1.0, 14.3), (6.2, 5.2, 3.8), "spine2", rot=(-12, 0, 0))
box((0, 1.5, 16.0), (5.4, 4.4, 1.8), "spine2", rot=(-15, 0, 0))
for s in (1, -1):  # flanks / pectorals give the torso a rounder silhouette
    box((3.3 * s, -0.2, 10.4), (0.6, 4.4, 3.4), "spine1", SKIN_DARK, rot=(-8, 0, 0))
    box((2.4 * s, 3.2, 14.6), (1.8, 0.8, 2.4), "spine2", rot=(-12, 0, 0))
box((0, 2.45, 9.3), (4.6, 0.3, 2.8), "hips", BELLY)
box((0, 3.2, 11.5), (4.4, 0.3, 3.4), "spine1", BELLY, rot=(-8, 0, 0))
box((0, 3.6, 14.2), (3.6, 0.3, 3.2), "spine2", BELLY, rot=(-12, 0, 0))

# Neck
seg((0, 1.4, 15.6), (0, 2.1, 17.5), 4.4, 4.0, "neck1")
seg((0, 2.0, 17.2), (0, 2.7, 18.6), 3.8, 3.5, "neck2")
box((0, 3.75, 16.9), (2.8, 0.3, 2.4), "neck1", BELLY, rot=(-25, 0, 0))

# Head (upper jaw); bottom faces show as the mouth roof when the jaw opens
box((0, 3.6, 19.0), (3.9, 3.4, 2.5), "head", bottom=MOUTH)
box((0, 6.1, 18.55), (3.0, 3.4, 1.6), "head", bottom=MOUTH)
box((0, 7.95, 18.45), (2.4, 0.6, 1.3), "head")
box((0, 3.2, 20.35), (2.6, 2.2, 0.4), "head", SKIN_DARK)
for s in (1, -1):
    box((1.25 * s, 4.75, 20.0), (1.5, 1.8, 0.6), "head", SKIN_DARK, rot=(0, 0, 10 * s))  # brow ridge
    box((1.95 * s, 3.6, 18.2), (0.5, 2.4, 1.6), "head")                                  # cheek
    # eye sits 0.1 unit proud of the socket (closer faces z-fight at a distance)
    box((1.98 * s, 4.4, 19.4), (0.12, 1.7, 1.1), "head", SOCKET)
    box((2.1 * s, 4.4, 19.4), (0.1, 1.3, 0.75), "head", EYE)
    box((0.6 * s, 8.26, 18.75), (0.4, 0.1, 0.3), "head", BLACK)                           # nostril
    for y in (4.4, 5.15, 5.9, 6.65, 7.4):
        box((1.28 * s, y, 17.6), (0.32, 0.32, 0.5), "head", TOOTH)
for x in (-0.8, -0.4, 0, 0.4, 0.8):
    box((x, 7.95, 17.65), (0.28, 0.3, 0.45), "head", TOOTH)
for i, z in enumerate((19.8, 19.2)):
    box((0, 1.7 - i * 0.2, z + 0.6), (0.4, 0.9, 0.9 - i * 0.3), "head", PLATE)

# Lower jaw; its top face is the mouth floor
box((0, 5.3, 17.35), (2.9, 5.2, 0.9), "jaw", top=MOUTH)
box((0, 7.6, 17.35), (2.3, 0.8, 0.8), "jaw")
box((0, 3.6, 17.0), (2.7, 1.8, 0.9), "jaw")
box((0, 4.6, 17.85), (1.6, 3.4, 0.15), "jaw", TONGUE)
for s in (1, -1):
    for y in (5.0, 5.8, 6.6, 7.3):
        box((1.12 * s, y, 17.95), (0.28, 0.28, 0.42), "jaw", TOOTH)

# Arms
for s, sfx in ((1, "_l"), (-1, "_r")):
    S, E, W, F = ARM[s]
    box(S, (2.1, 2.1, 2.1), "uarm" + sfx)
    seg(S, E, 1.7, 1.8, "uarm" + sfx)
    seg(E, W, 1.5, 1.5, "farm" + sfx)
    seg(W, F, 1.7, 0.9, "hand" + sfx, ext=0.2)
    for dx in (-0.55, 0, 0.55):
        seg(F + Vector((dx, -0.1, 0)), F + Vector((dx, 0.6, -0.9)), 0.32, 0.32, "hand" + sfx, CLAW, ext=0.1)

# Tail: segments overlap a little so bending doesn't open gaps; belly scales underneath
for i in range(8):
    w = TAIL_W[i]
    seg(TAIL_PTS[i], TAIL_PTS[i + 1], w, w * 0.92, f"tail{i + 1}", ext=0.45, bottom=BELLY)

# Dorsal plates: three rows down the back and neck, one row (two rows near the base) on the tail
BACK = [("hips", (-3.1, 9.4), 2.6, 1.8), ("spine1", (-2.5, 11.3), 3.4, 2.2), ("spine1", (-2.1, 12.8), 3.8, 2.4),
        ("spine2", (-1.7, 14.4), 4.0, 2.4), ("spine2", (-1.1, 15.9), 3.3, 2.0), ("neck1", (-0.4, 17.1), 2.5, 1.6),
        ("neck2", (0.4, 18.3), 1.6, 1.1)]
for b, (y, z), h, l in BACK:
    plate((0, y, z), h, l, b)
    if b not in ("neck2",):
        for s in (1, -1):
            plate((1.15 * s, y + 0.25, z - 0.3), h, l, b, scale=0.62)
for i in range(8):
    p0, p1 = TAIL_PTS[i], TAIL_PTS[i + 1]
    mid = (p0 + p1) / 2
    d = p1 - p0
    pitch = math.degrees(math.atan2(-d.z, -d.y))  # follow the tail's downward slope
    top = mid + Vector((0, 0, TAIL_W[i] * 0.46))
    plate(top, 2.8 - i * 0.3, 1.8 - i * 0.12, f"tail{i + 1}", pitch=pitch, lean=15)
    if i < 4:
        for s in (1, -1):
            plate(top + Vector((0.8 * s, 0.3, -0.2)), 2.8 - i * 0.3, 1.8, f"tail{i + 1}", pitch=pitch, lean=15, scale=0.55)

# --- build mesh ---------------------------------------------------------------------
CORNERS = [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),
           (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]
FACES = {  # corner indices, and which local axes (u, v) the texture follows
    "bottom": ((0, 3, 2, 1), (0, 1)), "top": ((4, 5, 6, 7), (0, 1)),
    "front": ((3, 7, 6, 2), (0, 2)), "back": ((0, 1, 5, 4), (0, 2)),
    "right": ((1, 2, 6, 5), (1, 2)), "left": ((0, 4, 7, 3), (1, 2)),
}

def face_uvs(tile, local, axes):
    a, b = axes
    us = [p[a] for p in local]; vs = [p[b] for p in local]
    du, dv = max(us) - min(us), max(vs) - min(vs)
    tx, ty = (tile % 4) * TILE, (tile // 4) * TILE
    if tile in FIT_TILES:
        w = h = TILE - 1; ox = oy = 0.5
    else:
        w, h = min(du * DENSITY, TILE - 1), min(dv * DENSITY, TILE - 1)
        ox, oy = rng.uniform(0.5, TILE - 0.5 - w), rng.uniform(0.5, TILE - 0.5 - h)
    res = []
    for u, v in zip(us, vs):
        fu = (u - min(us)) / du if du else 0
        fv = (v - min(vs)) / dv if dv else 0
        px, py = tx + ox + fu * w, ty + oy + (1 - fv) * h  # image y grows downwards
        res.append((px / ATLAS, 1 - py / ATLAS))
    return res

verts, faces, uvs, vert_bone = [], [], [], []
for c, s, q, b, tile, overrides in boxes:
    base = len(verts)
    local = [Vector((cx * s[0] / 2, cy * s[1] / 2, cz * s[2] / 2)) for cx, cy, cz in CORNERS]
    for p in local:
        verts.append(tuple(c + q @ p)); vert_bone.append(b)
    for name, (idx, axes) in FACES.items():
        faces.append(tuple(base + k for k in idx))
        uvs.append(face_uvs(overrides.get(name, tile), [local[k] for k in idx], axes))

me = bpy.data.meshes.new("gojira")
me.from_pydata(verts, [], faces)
uv = me.uv_layers.new(name="UVMap")
for poly, fuv in zip(me.polygons, uvs):
    for li, co in zip(poly.loop_indices, fuv):
        uv.data[li].uv = co
bm = bmesh.new(); bm.from_mesh(me)
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bm.to_mesh(me); bm.free()
me.update()

obj = bpy.data.objects.new("gojira", me)
scn.collection.objects.link(obj)
me.materials.append(bpy.data.materials.new("gojira"))

# --- armature -------------------------------------------------------------------------
arm_data = bpy.data.armatures.new("Armature")
arm = bpy.data.objects.new("Armature", arm_data)
scn.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
for name, (h, t, _) in BONES.items():
    eb = arm_data.edit_bones.new(name); eb.head, eb.tail = h, t
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
# Rotations in armature-space degrees, relative to the parent's posed frame:
# X = pitch (+ tips the bone's far end up / swings a hanging leg forward), Y = roll, Z = yaw.
# loc = offset in armature units.
for pb in arm.pose.bones:
    pb.rotation_mode = "QUATERNION"

def key(frame, loc=None, **rots):
    loc = loc or {}
    for name in BONES:
        pb = arm.pose.bones[name]
        rest = pb.bone.matrix_local.to_quaternion()
        rx, ry, rz = rots.get(name, (0, 0, 0))
        q = Euler((math.radians(rx), math.radians(ry), math.radians(rz)), "XYZ").to_quaternion()
        pb.rotation_quaternion = rest.inverted() @ q @ rest
        pb.location = rest.inverted() @ Vector(loc.get(name, (0, 0, 0)))
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        pb.keyframe_insert("location", frame=frame)

def both(prefix, l, r=None):
    return {prefix + "_l": l, prefix + "_r": r if r is not None else l}

def tail_wave(phase, yaw_amp, pitch=0.0, lag=0.6):
    return {f"tail{i}": (pitch, 0, yaw_amp * math.sin(phase - i * lag)) for i in range(1, 9)}

TAU = 2 * math.pi

# stand 0-60: breathing, slow tail sway
for f in range(0, 61, 3):
    t = TAU * f / 60
    br = math.sin(t)
    key(f, spine2=(2 * br, 0, 0), neck1=(-1.5 * br, 0, 0), head=(2 * math.sin(t + 0.6), 0, 0),
        jaw=(-3 * (0.5 + 0.5 * br), 0, 0), **both("uarm", (3 * br, 0, 0)), **tail_wave(t, 5, lag=0.5))

# walk 70-110: one full stride cycle (left + right step).
# Stance: the sole moves backwards at constant speed (the body moves at constant speed, so
# anything else slides) and root drops by however much the ankle's arc lifts the sole. That
# plants the foot and gives the bob: lowest at footfall, highest mid-stance.
# Swing: eased return with the knee bent.
# gojira/init.lua sets WALK_CYCLE_NODES from WALK_CYCLE_UNITS (printed at the end).
A = 22
LEG_V = LEG[1][2] - LEG[1][0]                           # hip -> ankle at rest
LEG_R = math.hypot(LEG_V.y, LEG_V.z)
LEG_PHI = math.degrees(math.atan2(-LEG_V.y, -LEG_V.z))  # thigh angle that puts the ankle under the hip
WALK_CYCLE_UNITS = 2 * 2 * LEG_R * math.sin(math.radians(A))
for f in range(70, 111):
    ph = TAU * (f - 70) / 40
    pose = {}
    drop = 0.0
    for s, sfx, off in ((1, "_l", 0), (-1, "_r", math.pi)):
        p = (ph + off) % TAU
        if p <= math.pi + 1e-9:                 # stance
            swing = 0.0
            rel = math.degrees(math.asin(math.sin(math.radians(A)) * (1 - 2 * p / math.pi)))
            drop = max(drop, -LEG_V.z - LEG_R * math.cos(math.radians(rel)))
        else:
            swing = -math.sin(p)                # 0 at lift-off/landing, 1 mid-swing
            rel = A * math.cos(p)
        thigh = LEG_PHI + rel + 12 * swing
        shin = -38 * swing
        pose["thigh" + sfx] = (thigh, 0, 0)
        pose["shin" + sfx] = (shin, 0, 0)
        pose["foot" + sfx] = (-(thigh + shin) + 10 * swing, 0, 0)  # keep the sole flat, toes lift in swing
        pose["uarm" + sfx] = (-12 * math.cos(p), 0, 0)
        pose["farm" + sfx] = (8 + 6 * math.sin(p), 0, 0)
    key(f, loc={"root": (0, 0, -drop)},
        hips=(2, 3 * math.sin(ph), 5 * math.cos(ph)),
        spine1=(-2, 0, -3 * math.cos(ph)), spine2=(-2, -2 * math.sin(ph), -3 * math.cos(ph)),
        neck1=(1 - 1.5 * math.cos(2 * ph), 0, 0), head=(1.5 * math.cos(2 * ph), 0, 2 * math.cos(ph)),
        **pose, **tail_wave(ph, 8, pitch=-1.5))

# punch 120-140: bite lunge with arm swipe and tail lash. The snap comes early (frame 126)
# because mcl_mobs deals the damage when the animation starts.
key(120)
key(123, spine1=(4, 0, 0), spine2=(8, 0, 0), neck1=(10, 0, 0), neck2=(6, 0, 0), head=(14, 0, 0),
    jaw=(-12, 0, 0), **both("uarm", (-20, 0, 0)), **tail_wave(0, 12))
key(126, spine1=(-10, 0, 0), spine2=(-14, 0, 0), neck1=(-14, 0, 0), neck2=(-8, 0, 0), head=(-14, 0, 0),
    jaw=(-40, 0, 0), **both("uarm", (50, 0, 0)), **both("farm", (25, 0, 0)), **both("hand", (20, 0, 0)),
    **tail_wave(math.pi, 12))
key(140)

# breath 150-200: rear back, thrust forward, hold the blast with jaw wide open, recover
key(150)
rear = dict(hips=(5, 0, 0), spine1=(8, 0, 0), spine2=(12, 0, 0), neck1=(15, 0, 0), neck2=(10, 0, 0),
            head=(18, 0, 0), jaw=(-15, 0, 0), **both("uarm", (-25, 0, 0)), **both("farm", (20, 0, 0)),
            **{f"tail{i}": (-4, 0, 0) for i in range(1, 9)})
key(160, **rear)
for f, yaw in ((166, 0), (172, 3), (178, -3), (184, 3), (190, -3), (194, 0)):
    # -36 deg in total: the head points at a target ~15 nodes away, not at his own feet
    key(f, hips=(-6, 0, 0), spine1=(-5, 0, 0), spine2=(-7, 0, 0), neck1=(-8, 0, yaw), neck2=(-6, 0, 0),
        head=(-4, 0, yaw), jaw=(-50, 0, 0), **both("uarm", (30, 0, 0)), **both("farm", (15, 0, 0)),
        **both("hand", (-20, 0, 0)), **{f"tail{i}": (1, 0, 0) for i in range(1, 9)})
key(200)

# die 210-240: knees buckle, topple onto the side, tail goes limp
key(210)
buckle = dict(**both("thigh", (35, 0, 0)), **both("shin", (-65, 0, 0)), **both("foot", (30, 0, 0)),
              spine1=(-10, 0, 0), spine2=(-10, 0, 0), head=(-10, 0, 0), jaw=(-20, 0, 0))
# Legs hang from root, so root (not hips) drops by what the folded legs lift the soles (2.8).
# Rolling about the ground line would bury one flank, so root rises by about half his width.
# Tail pitch - = tip up (keeps it out of the ground); lying on his side, tail yaw + and
# neck/head yaw - droop them onto the ground.
key(218, loc={"root": (0, 0, -2.8)}, **buckle, **{f"tail{i}": (-1.5, 0, 0) for i in range(1, 9)})
lying = dict(buckle, neck1=(0, 0, -10), head=(0, 0, -15), jaw=(-35, 0, 0),
             **{f"tail{i}": (-1.5, 0, 2) for i in range(1, 9)})
key(232, loc={"root": (0, 0, 3.6)}, root=(0, 80, 0), **lying)
key(240, loc={"root": (0, 0, 4.0)}, root=(0, 90, 0), **lying)

# breath_up 250-300: same rear-up, then the blast goes up at a flying target (Mothra) instead
# of down at the ground: about +45 deg head pitch in total, chest thrown back.
key(250)
key(260, **rear)
for f, yaw in ((266, 0), (272, 3), (278, -3), (284, 3), (290, -3), (294, 0)):
    key(f, hips=(4, 0, 0), spine1=(6, 0, 0), spine2=(8, 0, 0), neck1=(10, 0, yaw), neck2=(8, 0, 0),
        head=(4, 0, yaw), jaw=(-50, 0, 0), **both("uarm", (-10, 0, 0)), **both("farm", (25, 0, 0)),
        **both("hand", (-20, 0, 0)), **{f"tail{i}": (3, 0, 0) for i in range(1, 9)})
key(300)

scn.frame_start, scn.frame_end = 0, 300
arm.animation_data.action.name = "gojira"

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

# --- self-check, and the numbers gojira/init.lua needs -------------------------------------
UNIT = 0.75  # nodes per unit at visual_size 7.5

def posed(frame):
    scn.frame_set(frame)
    dg = bpy.context.evaluated_depsgraph_get()
    return [v.co.copy() for v in obj.evaluated_get(dg).data.vertices]

walk_min = [min(v.z for v in posed(f)) for f in range(70, 111, 5)]
print("WALK_CYCLE_UNITS %.3f (%.2f nodes); lowest vertex per walk frame: %s"
      % (WALK_CYCLE_UNITS, WALK_CYCLE_UNITS * UNIT, " ".join("%.2f" % z for z in walk_min)))
assert all(abs(z) < 0.15 for z in walk_min), "walk: stance foot not on the ground"
for f in (218, 240):
    zs = [v.z for v in posed(f)]
    print("die frame %d: lowest vertex %.2f, highest %.2f" % (f, min(zs), max(zs)))
for name, frame in (("breath", 166), ("breath_up", 266)):
    scn.frame_set(frame)
    bpy.context.evaluated_depsgraph_get()
    hb = arm.pose.bones["head"]
    to_posed = hb.matrix @ hb.bone.matrix_local.inverted()
    mouth = to_posed @ Vector((0, 7.0, 17.7))
    fwd = to_posed.to_quaternion() @ Vector((0, 1, 0))
    print("%s mouth (frame %d): forward %.2f, height %.2f units (%.2f / %.2f nodes), head pitch %.1f deg"
          % (name, frame, mouth.y, mouth.z, mouth.y * UNIT, mouth.z * UNIT, math.degrees(math.atan2(fwd.z, fwd.y))))
