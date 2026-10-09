"""Builds the pilot: a girl after Nausicaa, standing in a T pose, as one continuous rigged mesh.

Run with Blender 4.3:
    blender -b --factory-startup --python art/build_girl.py
It writes art/girl.blend (to open and edit by hand) and models/girl.glb (what the game loads).

How she is made:
  1. A stick figure of points with a thickness at each one is skinned into a smooth body
     (Blender's Skin modifier), so the limbs flow into the torso with no joins.
  2. The flare of her tunic and the mass of her short hair are added as rough shapes.
  3. Everything is fused into a single watertight surface (a voxel remesh) and smoothed.
  4. Each face gets a material by where it is on the body: skin, hair, eyes, tunic, belt,
     gloves, trousers, boots. The game repaints these by name with its cel shader.
  5. A skeleton is put inside and every vertex is tied to the nearest bones.

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
# 1. The stick figure. Each point: where it is, and how thick the body is there (across, front to back).

POINTS = {
    "hips": ((0, 0, 0.82), (0.105, 0.085)),
    "spine": ((0, 0, 0.95), (0.085, 0.07)),
    "chest": ((0, 0, 1.08), (0.1, 0.078)),
    "neck": ((0, 0, 1.22), (0.058, 0.05)),
    "head": ((0, -0.005, 1.365), (0.098, 0.102)),
    "crown": ((0, 0.0, 1.43), (0.085, 0.09)),
}
for side, sx in (("L", 1.0), ("R", -1.0)):
    POINTS["shoulder_" + side] = ((0.15 * sx, 0, 1.2), (0.05, 0.05))
    POINTS["elbow_" + side] = ((0.39 * sx, 0, 1.2), (0.036, 0.036))
    POINTS["wrist_" + side] = ((0.61 * sx, 0, 1.2), (0.033, 0.03))
    POINTS["hand_" + side] = ((0.69 * sx, 0, 1.2), (0.034, 0.02))
    POINTS["hip_" + side] = ((0.085 * sx, 0, 0.8), (0.074, 0.074))
    POINTS["knee_" + side] = ((0.085 * sx, 0, 0.42), (0.05, 0.05))
    POINTS["shin_" + side] = ((0.085 * sx, 0, 0.3), (0.052, 0.052))
    POINTS["ankle_" + side] = ((0.085 * sx, 0, 0.07), (0.042, 0.042))
    POINTS["toe_" + side] = ((0.085 * sx, -0.13, 0.03), (0.04, 0.028))

LINKS = [("hips", "spine"), ("spine", "chest"), ("chest", "neck"), ("neck", "head"), ("head", "crown")]
for side in ("L", "R"):
    LINKS += [
        ("chest", "shoulder_" + side), ("shoulder_" + side, "elbow_" + side),
        ("elbow_" + side, "wrist_" + side), ("wrist_" + side, "hand_" + side),
        ("hips", "hip_" + side), ("hip_" + side, "knee_" + side), ("knee_" + side, "shin_" + side),
        ("shin_" + side, "ankle_" + side), ("ankle_" + side, "toe_" + side),
    ]


def skinned_body():
    names = list(POINTS)
    mesh = bpy.data.meshes.new("stick")
    mesh.from_pydata([POINTS[n][0] for n in names], [(names.index(a), names.index(b)) for a, b in LINKS], [])
    obj = bpy.data.objects.new("stick", mesh)
    scene.collection.objects.link(obj)
    obj.modifiers.new("skin", "SKIN")
    for i, vert in enumerate(mesh.skin_vertices[0].data):
        vert.radius = POINTS[names[i]][1]
        vert.use_root = names[i] == "hips"
    smooth = obj.modifiers.new("smooth", "SUBSURF")
    smooth.levels = 2
    done = bpy.data.meshes.new_from_object(obj.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(obj)
    return done


# ---------------------------------------------------------------------------------------------
# 2. The tunic's flare and the hair, as rough shapes to be fused in.

def tunic_flare():
    bm = bmesh.new()
    # Narrow at the waist, wide at the hem.
    bmesh.ops.create_cone(bm, cap_ends=True, segments=28, radius1=0.2, radius2=0.1, depth=0.3)
    for v in bm.verts:
        v.co.z += 0.74
        v.co.y *= 0.88
    mesh = bpy.data.meshes.new("flare")
    bm.to_mesh(mesh)
    bm.free()
    return mesh


def hair_mass():
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=14, radius=1.0)
    for v in bm.verts:
        # A cap over the top and back of the head, down to the jaw: a short bob.
        v.co = Vector((v.co.x * 0.124, v.co.y * 0.122 + 0.032, v.co.z * 0.118 + 1.4))
        # Longer at the back, and swept out a little at the bottom edge.
        if v.co.z < 1.36 and v.co.y > 0.0:
            v.co.z -= 0.035
            v.co.y += 0.012
    mesh = bpy.data.meshes.new("hair")
    bm.to_mesh(mesh)
    bm.free()
    return mesh


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
    remesh.voxel_size = 0.013
    remesh.use_smooth_shade = True
    soften = obj.modifiers.new("soften", "SMOOTH")
    soften.factor = 0.6
    soften.iterations = 4
    done = bpy.data.meshes.new_from_object(obj.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(obj)
    done.name = "girl"
    for poly in done.polygons:
        poly.use_smooth = True
    return done


# ---------------------------------------------------------------------------------------------
# 4. Materials, by place on the body.

COLOURS = {
    "skin": (0.95, 0.76, 0.62),
    "hair": (0.55, 0.25, 0.12),
    "eye": (0.12, 0.09, 0.08),
    "tunic": (0.2, 0.42, 0.78),
    "belt": (0.45, 0.3, 0.18),
    "glove": (0.8, 0.66, 0.46),
    "trousers": (0.93, 0.9, 0.82),
    "boot": (0.5, 0.34, 0.22),
}


def part_of(c):
    """Which material a face belongs to, from the middle of the face."""
    x, y, z = abs(c.x), c.y, c.z
    if x > 0.17 and z > 1.05:
        # An arm: sleeve to past the elbow, then a long glove.
        return "glove" if x > 0.43 else "tunic"
    if z > 1.262:
        if z < 1.3 and y < 0.03:
            return "skin"
        hair = y > -0.03 or z > 1.418 or (x > 0.085 and z > 1.33)
        if not hair and abs(z - 1.372) < 0.017 and 0.022 < x < 0.058 and y < -0.07:
            return "eye"
        return "hair" if hair else "skin"
    if z > 0.585:
        return "belt" if 0.875 < z < 0.905 else "tunic"
    if z > 0.33:
        return "trousers"
    return "boot"


def paint(mesh):
    names = list(COLOURS)
    for name in names:
        mat = bpy.data.materials.new(name)
        mat.diffuse_color = (*COLOURS[name], 1.0)
        mat.use_nodes = True
        mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*COLOURS[name], 1.0)
        mesh.materials.append(mat)
    for poly in mesh.polygons:
        poly.material_index = names.index(part_of(poly.center))


# ---------------------------------------------------------------------------------------------
# 5. The skeleton, and which bones move which vertices.

BONES = [
    # name, head, tail, parent
    ("hips", (0, 0, 0.82), (0, 0, 0.95), None),
    ("spine", (0, 0, 0.95), (0, 0, 1.08), "hips"),
    ("chest", (0, 0, 1.08), (0, 0, 1.22), "spine"),
    ("neck", (0, 0, 1.22), (0, 0, 1.3), "chest"),
    ("head", (0, 0, 1.3), (0, 0, 1.5), "neck"),
]
for side, sx in (("L", 1.0), ("R", -1.0)):
    BONES += [
        ("upper_arm_" + side, (0.15 * sx, 0, 1.2), (0.39 * sx, 0, 1.2), "chest"),
        ("forearm_" + side, (0.39 * sx, 0, 1.2), (0.61 * sx, 0, 1.2), "upper_arm_" + side),
        ("hand_" + side, (0.61 * sx, 0, 1.2), (0.71 * sx, 0, 1.2), "forearm_" + side),
        ("thigh_" + side, (0.085 * sx, 0, 0.8), (0.085 * sx, 0, 0.42), "hips"),
        ("shin_" + side, (0.085 * sx, 0, 0.42), (0.085 * sx, 0, 0.07), "thigh_" + side),
        ("foot_" + side, (0.085 * sx, 0, 0.07), (0.085 * sx, -0.14, 0.02), "shin_" + side),
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
    ribs, one leg from tugging the other, and the legs from tugging the tunic's skirt."""
    x, y, z = co.x, co.y, co.z
    side = 1.0 if name.endswith("_L") else -1.0
    if name.startswith(("upper_arm", "forearm", "hand")):
        return x * side > 0.12 and z > 1.0
    if name.startswith(("thigh", "shin", "foot")):
        return x * side > -0.005 and z < 0.66
    if name == "head":
        return z > 1.3
    if name == "neck":
        return 1.2 < z < 1.36
    return z > 0.58 and abs(x) < 0.22


def distance_to_bone(co, head, tail):
    along = tail - head
    t = max(0.0, min(1.0, (co - head).dot(along) / along.length_squared))
    return (co - (head + along * t)).length


def bind(body, rig):
    groups = {name: body.vertex_groups.new(name=name) for name, _, _, _ in BONES}
    ends = {name: (Vector(head), Vector(tail)) for name, head, tail, _ in BONES}
    for vert in body.data.vertices:
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

mesh = fuse([skinned_body(), tunic_flare(), hair_mass()])
paint(mesh)
girl = bpy.data.objects.new("girl", mesh)
scene.collection.objects.link(girl)
rig = build_rig()
bind(girl, rig)
print("girl: %d vertices, %d faces" % (len(mesh.vertices), len(mesh.polygons)))

os.makedirs(os.path.join(ROOT, "models"), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "girl.blend"))
for obj in scene.objects:
    obj.select_set(True)
bpy.ops.export_scene.gltf(
    filepath=os.path.join(ROOT, "models", "girl.glb"), export_format="GLB", use_selection=True,
    export_animations=False, export_yup=True)
print("wrote models/girl.glb")
