# Builds kaiju/mothra/models/mothra.glb (blocky skinned + animated giant moth).
#   blender -b --factory-startup --python tools/mothra_model.py -- kaiju/mothra/models/mothra.glb
# Same conventions as tools/gojira_model.py: Blender Z-up, faces +Y, 10 units = 1 node at
# visual_size 1, scene fps 1 (glTF seconds == frames), rigid per-box skinning, 256px atlas.
# Body length ~11 units, wingspan ~33 units; the mob uses visual_size 8.
import bpy, bmesh, sys, math
from mathutils import Euler, Vector

out = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)
scn = bpy.context.scene
scn.render.fps = 1

(FOREWING, HINDWING, FUR_BROWN, FUR_WHITE, ABD_TAN, ABD_CREAM, EYE, ANTENNA,
 LEG, FUR_ORANGE) = range(10)
# Atlas rectangles (x, y, w, h); must match RECTS in tools/mothra_texture.py.
RECTS = {FOREWING: (0, 0, 128, 64), HINDWING: (128, 0, 96, 64),
         FUR_BROWN: (0, 64, 64, 64), FUR_WHITE: (64, 64, 64, 64),
         ABD_TAN: (128, 64, 64, 64), ABD_CREAM: (192, 64, 64, 64),
         EYE: (0, 128, 64, 64), ANTENNA: (64, 128, 64, 64),
         LEG: (128, 128, 64, 64), FUR_ORANGE: (192, 128, 64, 64)}
FIT_TILES = {FOREWING, HINDWING, EYE, ANTENNA}
ATLAS, DENSITY = 256, 12  # small model -> higher texel density

BONES = {}

def bone(name, head, tail, parent=None):
    BONES[name] = (Vector(head), Vector(tail), parent)

# Wing plates: (pivot at the root, span, chord, how far the leading edge sits ahead of the
# pivot, sweep in degrees (+ = forwards), tile). Span:chord matches the tile's aspect.
# The forewing sweeps forwards and the hindwing backwards so they barely overlap.
WINGS = {"wingf": ((1.6, 3.0, 2.95), 14.0, 7.0, 0.6, 12, FOREWING, 0.08),
         "wingh": ((1.5, 0.4, 2.75), 9.6, 6.4, 0.8, -25, HINDWING, 0.06)}
ANT = ((0.6, 6.0, 3.7), (2.6, 9.0, 5.9))  # antenna root -> tip on the +X side

def mirror(p, s):
    return (p[0] * s, p[1], p[2])

bone("root", (0, 0, 0), (0, 0, 1))
bone("body", (0, 1.0, 2.4), (0, 3.6, 2.4), "root")
bone("head", (0, 4.2, 2.6), (0, 6.4, 2.6), "body")
bone("abd1", (0, 0.8, 2.4), (0, -1.0, 2.2), "body")
bone("abd2", (0, -1.0, 2.2), (0, -2.6, 1.9), "abd1")
bone("abd3", (0, -2.6, 1.9), (0, -4.6, 1.5), "abd2")
LEG_Y = (3.0, 2.2, 1.4)
for s, sfx in ((1, "_l"), (-1, "_r")):
    bone("ant" + sfx, mirror(ANT[0], s), mirror(ANT[1], s), "head")
    for i, y in enumerate(LEG_Y):
        bone(f"leg{i + 1}{sfx}", (1.4 * s, y, 1.2), (2.7 * s, y + 0.4, 0.0), "body")
    for name, (pivot, span, *_) in WINGS.items():
        bone(name + sfx, mirror(pivot, s), mirror((pivot[0] + span, pivot[1], pivot[2]), s), "body")

boxes = []  # (center, size, quat, bone, tile, faces to emit or None for all, flip_u)

def box(c, s, b, tile, rot=(0, 0, 0), flip=False, only=None):
    q = Euler(tuple(math.radians(a) for a in rot), "XYZ").to_quaternion()
    boxes.append((Vector(c), s, q, b, tile, only, flip))

def seg(p0, p1, w, h, b, tile, ext=0.1, only=None):
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    q = d.normalized().to_track_quat("Y", "Z")
    boxes.append(((p0 + p1) / 2, (w, d.length + 2 * ext, h), q, b, tile, only, False))

# Head: orange fur, a white fur ruff wider than head and thorax, big blue compound eyes
box((0, 5.3, 2.6), (2.8, 2.2, 2.4), "head", FUR_ORANGE)
box((0, 3.9, 2.45), (4.6, 1.2, 4.2), "body", FUR_WHITE)
for s, sfx in ((1, "_l"), (-1, "_r")):
    box((1.5 * s, 5.6, 2.85), (0.8, 1.4, 1.4), "head", EYE)
    # antenna: crossed feather plates (one flat, one upright) so it reads from any angle;
    # only the patterned faces are emitted
    a0, a1 = mirror(ANT[0], s), mirror(ANT[1], s)
    seg(a0, a1, 1.6, 0.05, "ant" + sfx, ANTENNA, only=("top", "bottom"))
    seg(a0, a1, 0.05, 1.6, "ant" + sfx, ANTENNA, only=("left", "right"))

# Thorax (striped brown/white fur) and banded abdomen tapering backwards
box((0, 2.2, 2.4), (4.0, 3.2, 3.6), "body", FUR_BROWN)
box((0, 2.0, 4.3), (2.6, 2.4, 0.35), "body", FUR_WHITE)
ABD = [("abd1", (0, 0.0, 2.3), 2.4, ABD_TAN), ("abd1", (0, -0.9, 2.2), 2.2, ABD_CREAM),
       ("abd2", (0, -1.8, 2.05), 2.0, ABD_TAN), ("abd2", (0, -2.6, 1.9), 1.75, ABD_CREAM),
       ("abd3", (0, -3.4, 1.7), 1.45, ABD_TAN), ("abd3", (0, -4.2, 1.55), 1.1, ABD_CREAM)]
for b, c, w, t in ABD:
    box(c, (w * 1.55, 0.95, w * 1.5), b, t)
box((0, -4.9, 1.45), (0.8, 0.8, 0.8), "abd3", LEG)  # stinger tip

# Six legs, two segments each, rigid per leg
for s, sfx in ((1, "_l"), (-1, "_r")):
    for i, y in enumerate(LEG_Y):
        b = f"leg{i + 1}{sfx}"
        knee = (2.4 * s, y + 0.25, 0.7)
        seg((1.4 * s, y, 1.2), knee, 0.5, 0.5, b, LEG)
        seg(knee, (2.7 * s, y + 0.45, 0.0), 0.4, 0.4, b, LEG)

# Wings: thin plates, only the patterned top/bottom faces. The -X wings mirror the tile.
for s, sfx in ((1, "_l"), (-1, "_r")):
    for name, (pivot, span, chord, lead, sweep, tile, thick) in WINGS.items():
        rot = (0, 0, sweep * s)
        q = Euler((0, 0, math.radians(sweep * s)), "XYZ").to_quaternion()
        c = Vector(mirror(pivot, s)) + q @ Vector((s * span / 2, lead - chord / 2, 0))
        box(c, (span, chord, thick), name + sfx, tile, rot=rot, flip=(s < 0), only=("top", "bottom"))

# --- build mesh ---------------------------------------------------------------------
CORNERS = [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),
           (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]
FACES = {
    "bottom": ((0, 3, 2, 1), (0, 1)), "top": ((4, 5, 6, 7), (0, 1)),
    "front": ((3, 7, 6, 2), (0, 2)), "back": ((0, 1, 5, 4), (0, 2)),
    "right": ((1, 2, 6, 5), (1, 2)), "left": ((0, 4, 7, 3), (1, 2)),
}

def face_uvs(tile, local, axes, flip, name):
    a, b = axes
    us = [p[a] for p in local]; vs = [p[b] for p in local]
    umin, umax, vmin, vmax = min(us), max(us), min(vs), max(vs)
    tx, ty, tw, th = RECTS[tile]
    if tile in FIT_TILES:
        w, h = tw - 1, th - 1; ox = oy = 0.5
    else:
        w = min((umax - umin) * DENSITY, tw - 1); h = min((vmax - vmin) * DENSITY, th - 1)
        ox = oy = (tw - max(w, h)) / 2
    res = []
    for u, v in zip(us, vs):
        fu = (u - umin) / (umax - umin) if umax > umin else 0
        fv = (v - vmin) / (vmax - vmin) if vmax > vmin else 0
        # wing tiles: image x = root->tip (local X, mirrored on the -X side), image y =
        # leading edge (+Y) -> trailing edge
        if flip:
            fu = 1 - fu
        if tile == ANTENNA and name in ("top", "bottom"):
            fu, fv = fv, 1 - fu  # the shaft (image x) runs along the plate's length (local Y)
        px, py = tx + ox + fu * w, ty + oy + (1 - fv) * h
        res.append((px / ATLAS, 1 - py / ATLAS))
    return res

verts, faces, uvs, vert_bone = [], [], [], []
for c, s, q, b, tile, only, flip in boxes:
    base = len(verts)
    local = [Vector((cx * s[0] / 2, cy * s[1] / 2, cz * s[2] / 2)) for cx, cy, cz in CORNERS]
    for p in local:
        verts.append(tuple(c + q @ p)); vert_bone.append(b)
    for name, (idx, axes) in FACES.items():
        if only and name not in only:
            continue
        faces.append(tuple(base + k for k in idx))
        uvs.append(face_uvs(tile, [local[k] for k in idx], axes, flip, name))

me = bpy.data.meshes.new("mothra")
me.from_pydata(verts, [], faces)
uv = me.uv_layers.new(name="UVMap")
for poly, fuv in zip(me.polygons, uvs):
    for li, co in zip(poly.loop_indices, fuv):
        uv.data[li].uv = co
bm = bmesh.new(); bm.from_mesh(me)
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bm.to_mesh(me); bm.free()
me.update()

obj = bpy.data.objects.new("mothra", me)
scn.collection.objects.link(obj)
me.materials.append(bpy.data.materials.new("mothra"))

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

# --- animation ----------------------------------------------------------------------
# Armature-space degrees: X = pitch (+ = nose up), Y = roll, Z = yaw.
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

def wings(fore, hind, sweep=0.0):
    """fore/hind > 0 raise the wings; rotation about the body's long (Y) axis, mirrored.
    (A positive rotation about +Y lowers the +X side, hence the minus on the _l wings.)"""
    return {"wingf_l": (0, -fore, sweep), "wingf_r": (0, fore, -sweep),
            "wingh_l": (0, -hind, sweep * 0.5), "wingh_r": (0, hind, -sweep * 0.5)}

LEGS_TUCKED = {f"leg{i}{sfx}": (-35, 0, 0) for i in (1, 2, 3) for sfx in ("_l", "_r")}
TAU = 2 * math.pi

def flap_cycle(start, length, amp, mid, step, bob, pitch=0.0, extra=None):
    for f in range(start, start + length + 1, step):
        ph = TAU * (f - start) / length
        fore = mid + amp * math.cos(ph)
        hind = mid + amp * math.cos(ph - 0.6)          # hindwings lag behind
        r = dict(wings(fore, hind), **LEGS_TUCKED)
        r["body"] = (pitch + 3 * math.sin(ph), 0, 0)
        r["abd1"] = (-4 * math.sin(ph), 0, 0)
        r["abd2"] = (-4 * math.sin(ph - 0.5), 0, 0)
        r["abd3"] = (-5 * math.sin(ph - 1.0), 0, 0)
        r["ant_l"] = (6 * math.sin(ph), 0, 0)
        r["ant_r"] = (6 * math.sin(ph), 0, 0)
        if extra:
            r.update(extra(ph))
        # body rises on the downstroke
        key(f, loc={"root": (0, 0, -bob * math.cos(ph))}, **r)

# stand 0-40: hovering, slow shallow beats
flap_cycle(0, 40, 22, 8, 2, 0.25)
# fly 50-80: full, heavier beats
flap_cycle(50, 30, 42, 5, 2, 0.5, pitch=-4)
# punch / wing gust 90-120: raise high, body upright, then one huge downbeat and recover
key(90, **wings(5, 5), **LEGS_TUCKED)
key(100, body=(35, 0, 0), **wings(75, 65, sweep=-10), **LEGS_TUCKED)
key(106, body=(30, 0, 0), **wings(-55, -50, sweep=15), **LEGS_TUCKED)
key(112, body=(20, 0, 0), **wings(-40, -35), **LEGS_TUCKED)
key(120, **wings(5, 5), **LEGS_TUCKED)
# powder 130-170: hovering, fast fluttering, abdomen curled down, dusting below
flap_cycle(130, 10, 28, 15, 1, 0.15, pitch=10,
           extra=lambda ph: {"abd1": (12, 0, 0), "abd2": (14, 0, 0), "abd3": (16, 0, 0)})
flap_cycle(140, 10, 28, 15, 1, 0.15, pitch=10,
           extra=lambda ph: {"abd1": (12, 0, 0), "abd2": (14, 0, 0), "abd3": (16, 0, 0)})
flap_cycle(150, 10, 28, 15, 1, 0.15, pitch=10,
           extra=lambda ph: {"abd1": (12, 0, 0), "abd2": (14, 0, 0), "abd3": (16, 0, 0)})
flap_cycle(160, 10, 28, 15, 1, 0.15, pitch=10,
           extra=lambda ph: {"abd1": (12, 0, 0), "abd2": (14, 0, 0), "abd3": (16, 0, 0)})
# die 180-210: wings fold up, body rolls over and the legs curl
key(180, **wings(10, 10), **LEGS_TUCKED)
# (the roll is about the origin at her feet: lift the root so she lies on, not in, the ground)
key(195, loc={"root": (0, 0, 1.5)}, root=(0, 60, 0), **wings(80, 70), **{f"leg{i}{sfx}": (-70, 0, 0) for i in (1, 2, 3) for sfx in ("_l", "_r")})
key(210, loc={"root": (0, 0, 2.2)}, root=(0, 90, 0), **wings(85, 80), **{f"leg{i}{sfx}": (-80, 0, 0) for i in (1, 2, 3) for sfx in ("_l", "_r")})

scn.frame_start, scn.frame_end = 0, 210
arm.animation_data.action.name = "mothra"

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
