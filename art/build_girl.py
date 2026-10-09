"""Builds the pilot: a girl after Nausicaa, standing in a T pose, as one continuous rigged mesh.

Run with Blender 4.3:
    blender -b --factory-startup --python art/build_girl.py
then `godot --headless --path . --import` so the game picks the new model up.
It writes art/girl.blend (to open and edit by hand) and models/girl.glb (what the game loads).

How she is made:
  1. A stick figure of points with a thickness at each one is skinned into a smooth body
     (Blender's Skin modifier), so the limbs flow into the torso with no joins. The legs come
     out of a proper pelvis. The hands are gloved fists, modelled already curled round a bar,
     because all she ever does with them is hold the glider's handles.
  2. The snout of her gas mask is added as a rough shape and everything is fused into a single
     watertight surface (a voxel remesh) and smoothed a little.
  3. She is painted, vertex by vertex, by where each vertex is on the body: skin, scalp, the
     blue tunic with its cream trim, belt and buckle, gloves, trousers, boots with cuffs and
     soles, straps, the mask. Wherever two paints meet the mesh is first cut finer (twice), so
     the edges of the paint come out crisp instead of in voxel-sized steps. The paint is stored
     as vertex colours (alpha says how much a spot is woven cloth, for the game's shader).
  4. Her hard kit is added as clean separate shapes, each one flat colour with sharp edges:
     the goggles (the lenses are a second, glassy material), the mask's filter canister, and
     the pouch on her belt.
  5. A skeleton is put inside and every vertex is tied to the nearest bones.

Not here, because they move: her hair (scripts/locks.gd), and her skirt and scarf
(scripts/hair.gd), which the game makes and blows about itself.

She is 1.5 m tall, faces -Y (Blender's front), arms out along X. The game poses her itself.
"""

import math
import os

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

# ---------------------------------------------------------------------------------------------
# 1. The stick figure. Each point: where it is, and how thick the body is there.

POINTS = {
    "pelvis": ((0, 0.006, 0.8), (0.102, 0.09)),
    "hips": ((0, 0, 0.87), (0.096, 0.08)),
    "spine": ((0, 0, 0.96), (0.084, 0.07)),
    "chest": ((0, 0, 1.08), (0.1, 0.078)),
    "neck": ((0, 0, 1.22), (0.058, 0.05)),
    "head": ((0, -0.005, 1.365), (0.098, 0.102)),
    "crown": ((0, 0.0, 1.43), (0.085, 0.09)),
}
LINKS = [("pelvis", "hips"), ("hips", "spine"), ("spine", "chest"), ("chest", "neck"), ("neck", "head"), ("head", "crown")]
FINGERS = (-0.033, -0.011, 0.011, 0.033)
for side, sx in (("L", 1.0), ("R", -1.0)):
    def p(name, co, r):
        POINTS[name + "_" + side] = ((co[0] * sx, co[1], co[2]), r if isinstance(r, tuple) else (r, r))

    def link(a, b):
        LINKS.append((a if a in POINTS else a + "_" + side, b + "_" + side))

    p("shoulder", (0.15, 0, 1.2), 0.05)
    p("elbow", (0.39, 0, 1.2), 0.036)
    p("cuff", (0.44, 0, 1.2), 0.04)  # the top of the glove stands a little proud
    p("wrist", (0.61, 0, 1.2), 0.03)
    p("palm", (0.662, 0, 1.2), 0.033)
    link("chest", "shoulder"); link("shoulder", "elbow"); link("elbow", "cuff"); link("cuff", "wrist"); link("wrist", "palm")
    # A fist closed round a bar. The bar would run front to back under the knuckles, with its
    # middle at GRIP below; each finger goes out over the top of it, down the far side and back
    # underneath, and the thumb comes round under it from the near side to meet them.
    for i, fy in enumerate(FINGERS):
        p("f%d_a" % i, (0.7, fy, 1.197), 0.0118)
        p("f%d_b" % i, (0.732, fy, 1.174), 0.0115)
        p("f%d_c" % i, (0.735, fy, 1.136), 0.0112)
        p("f%d_d" % i, (0.708, fy, 1.112), 0.0108)
        p("f%d_e" % i, (0.679, fy, 1.117), 0.0102)
        link("palm", "f%d_a" % i)
        for a, b in ("ab", "bc", "cd", "de"):
            link("f%d_%s" % (i, a), "f%d_%s" % (i, b))
    p("t_a", (0.648, -0.04, 1.19), 0.0135)
    p("t_b", (0.658, -0.054, 1.156), 0.0125)
    p("t_c", (0.682, -0.05, 1.126), 0.0115)
    link("palm", "t_a"); link("t_a", "t_b"); link("t_b", "t_c")

    # The legs. They start inside the pelvis, close together and well up, and the thigh is
    # thick at the top, so each one swells out of the hip the way a leg does and there is a
    # crotch between them, not two posts stuck on the bottom of a barrel.
    p("hip", (0.068, 0.004, 0.775), (0.078, 0.082))
    p("thigh", (0.078, -0.004, 0.61), 0.064)
    p("knee", (0.082, -0.006, 0.42), 0.05)
    p("boot_top", (0.082, 0, 0.31), 0.06)  # the boot's cuff
    p("shin", (0.082, 0.004, 0.26), 0.052)
    p("ankle", (0.082, 0, 0.07), 0.043)
    p("toe", (0.082, -0.13, 0.03), (0.042, 0.03))
    link("pelvis", "hip"); link("hip", "thigh"); link("thigh", "knee"); link("knee", "boot_top")
    link("boot_top", "shin"); link("shin", "ankle"); link("ankle", "toe")

# Where the middle of the bar she is holding would be, in the T pose (her left hand).
GRIP = (0.703, 0.0, 1.154)


def skinned_body():
    names = list(POINTS)
    mesh = bpy.data.meshes.new("stick")
    mesh.from_pydata([POINTS[n][0] for n in names], [(names.index(a), names.index(b)) for a, b in LINKS], [])
    obj = bpy.data.objects.new("stick", mesh)
    scene.collection.objects.link(obj)
    obj.modifiers.new("skin", "SKIN")
    for i, vert in enumerate(mesh.skin_vertices[0].data):
        vert.radius = POINTS[names[i]][1]
        vert.use_root = names[i] == "pelvis"
    smooth = obj.modifiers.new("smooth", "SUBSURF")
    smooth.levels = 2
    done = bpy.data.meshes.new_from_object(obj.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(obj)
    # Flatten the backs of the hands: a hand is wide and thin, not round.
    for vert in done.vertices:
        if 0.625 < abs(vert.co.x) < 0.69 and vert.co.z > 1.2:
            vert.co.z = 1.2 + (vert.co.z - 1.2) * 0.6
    return done


# ---------------------------------------------------------------------------------------------
# 2. Her kit.

def shape(build, place):
    """A mesh from a bmesh primitive, with every vertex put through `place`."""
    bm = bmesh.new()
    build(bm)
    for v in bm.verts:
        v.co = Vector(place(v.co))
    mesh = bpy.data.meshes.new("part")
    bm.to_mesh(mesh)
    bm.free()
    return mesh


def ball(centre, radii):
    return shape(lambda bm: bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=14, radius=1.0),
                 lambda c: (centre[0] + c.x * radii[0], centre[1] + c.y * radii[1], centre[2] + c.z * radii[2]))


def box(centre, size):
    return shape(lambda bm: bmesh.ops.create_cube(bm, size=1.0),
                 lambda c: (centre[0] + c.x * size[0], centre[1] + c.y * size[1], centre[2] + c.z * size[2]))


def can(centre, radius, depth):
    """A short cylinder lying along Y (front to back)."""
    return shape(lambda bm: bmesh.ops.create_cone(bm, cap_ends=True, segments=24, radius1=radius, radius2=radius, depth=depth),
                 lambda c: (centre[0] + c.x, centre[1] + c.z, centre[2] + c.y))


LENS = (0.037, -0.108, 1.386)  # middle of her left goggle lens; the right is mirrored
LENS_RADIUS = 0.027


def fused_kit():
    # The gas mask's snout, over her nose and mouth. It is soft and sealed to her face, so it
    # is fused in with her; everything hard is added afterwards (see hard_kit).
    return [ball((0, -0.098, 1.322), (0.052, 0.046, 0.042))]


def crisp(mesh):
    """Give a hard shape sharp corners: split it along every edge that turns a real corner,
    so the smooth shading does not round them off."""
    bm = bmesh.new()
    bm.from_mesh(mesh)
    sharp = [e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > 0.6]
    bmesh.ops.split_edges(bm, edges=sharp)
    bm.to_mesh(mesh)
    bm.free()
    return mesh


def hard_kit():
    """Her hard kit: (mesh, paint, bone it rides on, material) for each piece."""
    parts = []
    # Goggles: a round frame over each eye with the lens set in the front of it.
    for sx in (1.0, -1.0):
        parts.append((can((LENS[0] * sx, LENS[1] + 0.003, LENS[2]), LENS_RADIUS + 0.007, 0.034), "frame", "head", 0))
        parts.append((can((LENS[0] * sx, LENS[1] - 0.0145, LENS[2]), LENS_RADIUS, 0.003), "frame", "head", 1))
    parts.append((box((0, -0.104, LENS[2]), (0.026, 0.014, 0.013)), "frame", "head", 0))  # the bridge
    # The filter canister on the front of the mask, its lip, and the pale grille on its face.
    parts.append((can((0, -0.15, 1.316), 0.03, 0.05), "canister", "head", 0))
    parts.append((can((0, -0.178, 1.316), 0.034, 0.012), "rubber", "head", 0))
    parts.append((can((0, -0.1845, 1.316), 0.02, 0.003), "mask", "head", 0))
    # A pouch on her belt at her right hip: the bag, its flap, and a brass stud.
    parts.append((box((-0.082, -0.074, 0.868), (0.066, 0.036, 0.074)), "leather", "hips", 0))
    parts.append((box((-0.082, -0.094, 0.886), (0.07, 0.008, 0.04)), "belt", "hips", 0))
    parts.append((ball((-0.082, -0.099, 0.876), (0.007, 0.005, 0.007)), "brass", "hips", 0))
    return [(crisp(mesh), paint, bone, material) for mesh, paint, bone, material in parts]


# ---------------------------------------------------------------------------------------------
# 3. Fuse it all into one surface.

def fuse(meshes):
    bm = bmesh.new()
    for mesh in meshes:
        bm.from_mesh(mesh)
    joined = bpy.data.meshes.new("joined")
    bm.to_mesh(joined)
    bm.free()
    obj = bpy.data.objects.new("joined", joined)
    scene.collection.objects.link(obj)
    remesh = obj.modifiers.new("remesh", "REMESH")
    remesh.mode = "VOXEL"
    remesh.voxel_size = 0.0068
    remesh.use_smooth_shade = True
    soften = obj.modifiers.new("soften", "SMOOTH")
    soften.factor = 0.5
    soften.iterations = 3
    done = bpy.data.meshes.new_from_object(obj.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(obj)
    done.name = "girl"
    for poly in done.polygons:
        poly.use_smooth = True
    return done


# ---------------------------------------------------------------------------------------------
# 4. Paint. Colours here are as they should look on screen. (They are stored as written: the
# glTF export and Godot's import between them already turn them into what the shader wants.
# Converting them here as well made her come out far too dark.)

PAINT = {
    "skin": (0.96, 0.78, 0.64), "blush": (0.95, 0.68, 0.6), "scalp": (0.44, 0.2, 0.1),
    "tunic": (0.2, 0.42, 0.8), "tunic_dark": (0.14, 0.31, 0.63), "trim": (0.95, 0.91, 0.8),
    "belt": (0.45, 0.3, 0.18), "brass": (0.82, 0.66, 0.26), "leather": (0.55, 0.37, 0.22),
    "glove": (0.82, 0.68, 0.48), "glove_dark": (0.62, 0.47, 0.3),
    "trousers": (0.94, 0.91, 0.83), "patch": (0.8, 0.76, 0.66),
    "boot": (0.5, 0.34, 0.22), "boot_light": (0.66, 0.48, 0.32), "sole": (0.2, 0.15, 0.12),
    "frame": (0.36, 0.24, 0.16), "strap": (0.3, 0.2, 0.14),
    "mask": (0.78, 0.8, 0.72), "canister": (0.42, 0.47, 0.42), "rubber": (0.2, 0.21, 0.2),
}
# How much of each paint is woven cloth (the game's shader gives cloth a faint weave).
CLOTH = {"tunic": 1.0, "tunic_dark": 1.0, "trim": 1.0, "trousers": 1.0, "patch": 1.0}


def paint_at(c):
    """Which paint goes on a spot of her body, from where it is in the T pose."""
    x, y, z = abs(c.x), c.y, c.z
    if x > 0.17 and z > 1.05:
        # An arm: sleeve with a cream cuff, then a long glove with a darker band at its top.
        if x > 0.447:
            # A seam round the wrist.
            return "glove_dark" if 0.6 < x < 0.612 else "glove"
        if x > 0.425:
            return "glove_dark"
        if x > 0.395:
            return "trim"
        # A seam round the shoulder.
        return "tunic_dark" if 0.165 < x < 0.178 else "tunic"
    if z > 1.262:
        if y < -0.062 and 1.276 < z < 1.366 and x < 0.058:
            # The snout, with a rubber edge where it seals to her face.
            return "rubber" if (x > 0.046 or z > 1.356 or z < 1.284) else "mask"
        # Straps round her head: the goggles' and the mask's.
        if 1.376 < z < 1.396:
            return "strap"
        if 1.312 < z < 1.332 and y > -0.075:
            return "rubber"
        if z < 1.3 and y < 0.03:
            return "skin"
        # Her scalp, under the hair the game puts on her.
        if y > -0.03 or z > 1.425 or (x > 0.082 and z > 1.33):
            return "scalp"
        # Her cheeks, where they show between the goggles and the mask.
        return "blush" if (1.34 < z < 1.368 and x > 0.042) else "skin"
    if z > 0.8:
        if 0.875 < z < 0.905:
            return "brass" if (x < 0.024 and y < -0.05) else "belt"
        if z > 1.19 and math.hypot(x, y) < 0.057:
            return "skin"  # her neck
        if x < 0.006 and y < 0.0 and z > 0.905:
            return "tunic_dark"  # the opening down her front
        return "tunic"
    if z > 0.335:
        return "patch" if (0.385 < z < 0.47 and y < -0.02) else "trousers"
    if z < 0.02:
        return "sole"
    if z > 0.285:
        return "boot_light"
    if 0.135 < z < 0.16 or 0.2 < z < 0.218:
        return "sole"  # two straps
    return "boot"


def refine(mesh):
    """Cut the mesh finer wherever two paints meet, so the edge between them is crisp."""
    bm = bmesh.new()
    bm.from_mesh(mesh)
    for _ in range(2):
        which = {v: paint_at(v.co) for v in bm.verts}
        meeting = [e for e in bm.edges if which[e.verts[0]] != which[e.verts[1]]]
        bmesh.ops.subdivide_edges(bm, edges=meeting, cuts=1)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = True


def add_kit(mesh, kit):
    """Join the hard kit on. Returns, for each vertex that belongs to a piece of it, that
    piece's (paint, bone)."""
    fixed = {}
    bm = bmesh.new()
    bm.from_mesh(mesh)
    for part, paint_name, bone, material in kit:
        bm.verts.ensure_lookup_table()
        bm.faces.ensure_lookup_table()
        first_vert, first_face = len(bm.verts), len(bm.faces)
        bm.from_mesh(part)
        bm.verts.ensure_lookup_table()
        bm.faces.ensure_lookup_table()
        for i in range(first_vert, len(bm.verts)):
            fixed[i] = (paint_name, bone)
        for i in range(first_face, len(bm.faces)):
            bm.faces[i].material_index = material
            bm.faces[i].smooth = True
    bm.to_mesh(mesh)
    bm.free()
    return fixed


def paint(mesh, fixed):
    for name in ("body", "glass"):
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        mesh.materials.append(mat)
    colours = mesh.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    for vert in mesh.vertices:
        which = fixed[vert.index][0] if vert.index in fixed else paint_at(vert.co)
        r, g, b = PAINT[which]
        colours.data[vert.index].color = (r, g, b, CLOTH.get(which, 0.0))
    mesh.color_attributes.active_color = colours
    mesh.color_attributes.render_color_index = 0


# ---------------------------------------------------------------------------------------------
# 5. The skeleton, and which bones move which vertices.

BONES = [
    # name, head, tail, parent
    ("hips", (0, 0, 0.82), (0, 0, 0.96), None),
    ("spine", (0, 0, 0.96), (0, 0, 1.08), "hips"),
    ("chest", (0, 0, 1.08), (0, 0, 1.22), "spine"),
    ("neck", (0, 0, 1.22), (0, 0, 1.3), "chest"),
    ("head", (0, 0, 1.3), (0, 0, 1.5), "neck"),
]
for side, sx in (("L", 1.0), ("R", -1.0)):
    BONES += [
        ("upper_arm_" + side, (0.15 * sx, 0, 1.2), (0.39 * sx, 0, 1.2), "chest"),
        ("forearm_" + side, (0.39 * sx, 0, 1.2), (0.61 * sx, 0, 1.2), "upper_arm_" + side),
        ("hand_" + side, (0.61 * sx, 0, 1.2), (0.71 * sx, 0, 1.2), "forearm_" + side),
        ("thigh_" + side, (0.072 * sx, 0, 0.79), (0.082 * sx, -0.006, 0.42), "hips"),
        ("shin_" + side, (0.082 * sx, -0.006, 0.42), (0.082 * sx, 0, 0.07), "thigh_" + side),
        ("foot_" + side, (0.082 * sx, 0, 0.07), (0.082 * sx, -0.14, 0.02), "shin_" + side),
    ]


def build_rig():
    arm = bpy.data.armatures.new("rig")
    rig = bpy.data.objects.new("rig", arm)
    scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for name, head, tail, parent in BONES:
        bone = arm.edit_bones.new(name)
        bone.head = head
        bone.tail = tail
        if parent:
            bone.parent = arm.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


def may_move(name, co):
    """Whether a bone is allowed to pull on a vertex at all. Keeps an arm from tugging the
    ribs, and one leg from tugging the other."""
    x, y, z = co.x, co.y, co.z
    side = 1.0 if name.endswith("_L") else -1.0
    if name.startswith(("upper_arm", "forearm", "hand")):
        return x * side > 0.12 and z > 1.0
    if name.startswith(("thigh", "shin", "foot")):
        return x * side > -0.004 and z < 0.85
    if name == "head":
        return z > 1.3
    if name == "neck":
        return 1.2 < z < 1.36
    return z > 0.7 and abs(x) < 0.22


def distance_to_bone(co, head, tail):
    along = tail - head
    t = max(0.0, min(1.0, (co - head).dot(along) / along.length_squared))
    return (co - (head + along * t)).length


def bind(body, rig, fixed):
    groups = {name: body.vertex_groups.new(name=name) for name, _, _, _ in BONES}
    ends = {name: (Vector(head), Vector(tail)) for name, head, tail, _ in BONES}
    for vert in body.data.vertices:
        if vert.index in fixed:
            groups[fixed[vert.index][1]].add([vert.index], 1.0, "REPLACE")
            continue
        pulls = []
        for name, (head, tail) in ends.items():
            if may_move(name, vert.co):
                pulls.append((1.0 / (distance_to_bone(vert.co, head, tail) + 0.012) ** 4, name))
        if not pulls:
            pulls = [(1.0, "hips")]
        pulls.sort(reverse=True)
        pulls = pulls[:3]
        total = sum(w for w, _ in pulls)
        for w, name in pulls:
            groups[name].add([vert.index], w / total, "REPLACE")
    body.parent = rig
    mod = body.modifiers.new("rig", "ARMATURE")
    mod.object = rig


# ---------------------------------------------------------------------------------------------

mesh = fuse([skinned_body()] + fused_kit())
refine(mesh)
fixed = add_kit(mesh, hard_kit())
paint(mesh, fixed)
girl = bpy.data.objects.new("girl", mesh)
scene.collection.objects.link(girl)
rig = build_rig()
bind(girl, rig, fixed)
print("girl: %d vertices, %d faces" % (len(mesh.vertices), len(mesh.polygons)))

os.makedirs(os.path.join(ROOT, "models"), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "girl.blend"))
for obj in scene.objects:
    obj.select_set(True)
bpy.ops.export_scene.gltf(
    filepath=os.path.join(ROOT, "models", "girl.glb"), export_format="GLB", use_selection=True,
    export_animations=False, export_yup=True, export_vertex_color="ACTIVE", export_all_vertex_colors=False)
print("wrote models/girl.glb")
