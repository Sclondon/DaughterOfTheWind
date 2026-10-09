extends Node3D
## The pilot: the girl built in Blender (art/build_girl.py -> models/girl.glb), one continuous
## skinned mesh on a skeleton. This script paints her with the cel shader and poses her.
##
## She is not animated from clips. Each frame the glider's model says where her hips are, how far
## she is bent forward, and where her hands and feet should be, and pose() works the skeleton
## out from that: the spine follows the hips, the head stays looking ahead, and each arm and leg
## is bent at the elbow or knee by just enough to reach (two-bone IK). So her hands stay on the
## handles and her feet on the deck whatever she does in between.
##
## Everything passed to pose() is in this node's own space, which is the glider's: forward is
## -Z, up is +Y, her right hand is +X.

const Toon := preload("res://scripts/toon.gd")
const Model := preload("res://models/girl.glb")

## What each of the model's materials is painted, by its name in Blender.
const COLOURS := {
	"skin": Color(0.96, 0.78, 0.64),
	"hair": Color(0.58, 0.27, 0.13),
	"eye": Color(0.12, 0.09, 0.08),
	"tunic": Color(0.2, 0.42, 0.8),
	"belt": Color(0.45, 0.3, 0.18),
	"glove": Color(0.82, 0.68, 0.48),
	"trousers": Color(0.94, 0.91, 0.83),
	"boot": Color(0.5, 0.34, 0.22),
}

var skeleton: Skeleton3D
## Nodes that ride on her head and on her chest, for the hair and the scarf to be pinned to.
var head_anchor: BoneAttachment3D
var chest_anchor: BoneAttachment3D

var _bone := {}  # name -> index
var _rest := {}  # name -> the bone's rest pose in the skeleton's space
var _along := {}  # name -> which way the bone points at rest
var _long := {}  # name -> its length
var _body: Node3D


func _ready() -> void:
	_body = Model.instantiate()
	# The model faces +Z as it comes in; the glider flies toward -Z.
	_body.rotation.y = PI
	add_child(_body)
	skeleton = _find(_body, "Skeleton3D") as Skeleton3D
	var mesh := _find(_body, "MeshInstance3D") as MeshInstance3D
	for surface in mesh.mesh.get_surface_count():
		var material: Material = mesh.mesh.surface_get_material(surface)
		var colour: Color = COLOURS.get(material.resource_name if material else "", Color.MAGENTA)
		mesh.set_surface_override_material(surface, Toon.paint(colour))
	# She is posed far from where the mesh was built, so do not cull her by her resting bounds.
	mesh.extra_cull_margin = 3.0

	for i in skeleton.get_bone_count():
		var bone: String = skeleton.get_bone_name(i)
		_bone[bone] = i
		_rest[bone] = skeleton.get_bone_global_rest(i)
	# Each bone points at the bone that carries on from it.
	var next := {"hips": "spine", "spine": "chest", "chest": "neck", "neck": "head"}
	for side: String in ["L", "R"]:
		next["upper_arm_" + side] = "forearm_" + side
		next["forearm_" + side] = "hand_" + side
		next["thigh_" + side] = "shin_" + side
		next["shin_" + side] = "foot_" + side
	for bone: String in next:
		var reach: Vector3 = (_rest[next[bone]] as Transform3D).origin - (_rest[bone] as Transform3D).origin
		_along[bone] = reach.normalized()
		_long[bone] = reach.length()

	head_anchor = BoneAttachment3D.new()
	skeleton.add_child(head_anchor)
	head_anchor.bone_name = "head"
	chest_anchor = BoneAttachment3D.new()
	skeleton.add_child(chest_anchor)
	chest_anchor.bone_name = "chest"


func _find(from: Node, type: String) -> Node:
	if from.is_class(type):
		return from
	for child: Node in from.get_children():
		var found: Node = _find(child, type)
		if found:
			return found
	return null


## A direction in the skeleton's space (up is +Y, her front is +Z, her left is +X) turned into
## the space of one of her bones, for pinning things to an anchor.
func in_bone(bone: String, direction: Vector3) -> Vector3:
	return (_rest[bone] as Transform3D).basis.inverse() * direction


## Pose her. `hips` is where her hips are; `lean` how far she is bent forward from upright
## (radians) and `roll` how far tipped to her right; `hands` and `feet` are where her wrists and
## ankles should be ([left, right]); `loose` (0..1) lets her feet hang from the shins instead of
## standing flat.
func pose(hips: Vector3, lean: float, roll: float, hands: Array, feet: Array, loose: float) -> void:
	# From this node's space into the skeleton's.
	var into: Transform3D = skeleton.global_transform.affine_inverse() * global_transform
	# In the skeleton's own space her front is +Z, so bending forward tips "up" toward +Z.
	var bend := Basis(Vector3.BACK, roll) * Basis(Vector3.RIGHT, lean)
	var hips_now := Transform3D(bend * (_rest["hips"] as Transform3D).basis, into * hips)
	skeleton.set_bone_global_pose(_bone["hips"], hips_now)
	# The spine keeps its shape and simply follows the hips.
	for bone: String in ["spine", "chest", "neck", "head"]:
		skeleton.reset_bone_pose(_bone[bone])
	# Her head stays looking where she is going, not at the deck.
	var head_now: Transform3D = skeleton.get_bone_global_pose(_bone["head"])
	head_now.basis = Basis(Vector3.BACK, roll * 0.5) * Basis(Vector3.RIGHT, lean * 0.22) * (_rest["head"] as Transform3D).basis
	skeleton.set_bone_global_pose(_bone["head"], head_now)

	var chest_now: Transform3D = skeleton.get_bone_global_pose(_bone["chest"])
	var carried: Transform3D = hips_now * (_rest["hips"] as Transform3D).affine_inverse()
	var sides := ["L", "R"]
	for i in 2:
		var side: String = sides[i]
		# Her left is +X in the skeleton's space.
		var outward: Vector3 = Vector3.RIGHT * (1.0 if i == 0 else -1.0)
		var shoulder: Vector3 = (chest_now * (_rest["chest"] as Transform3D).affine_inverse()) * (_rest["upper_arm_" + side] as Transform3D).origin
		# Elbows point down and a little out and back.
		_reach("upper_arm_" + side, "forearm_" + side, "hand_" + side, shoulder, into * (hands[i] as Vector3),
				Vector3(0, -1.0, -0.5) + outward * 0.6, 1.0)
		var hip: Vector3 = carried * (_rest["thigh_" + side] as Transform3D).origin
		# Knees point forward and a little out.
		_reach("thigh_" + side, "shin_" + side, "foot_" + side, hip, into * (feet[i] as Vector3),
				Vector3(0, 0.25, 1.0) + outward * 0.25, loose)


## Bend a limb of two bones so that its end reaches a target (as nearly as its length allows),
## with the joint pushed out toward `pole`. `follow` (0..1) is how much the end bone (hand or
## foot) turns with the lower bone instead of keeping its rest angle.
func _reach(upper: String, lower: String, end: String, from: Vector3, to: Vector3, pole: Vector3, follow: float) -> void:
	var first: float = _long[upper]
	var second: float = _long[lower]
	var span: Vector3 = to - from
	var far: float = clampf(span.length(), absf(first - second) + 0.01, first + second - 0.004)
	var toward: Vector3 = span.normalized() if span.length() > 0.0001 else Vector3.DOWN
	# The joint sits off the straight line by what the law of cosines says.
	var cos_at: float = clampf((first * first + far * far - second * second) / (2.0 * first * far), -1.0, 1.0)
	var aside: Vector3 = pole - toward * pole.dot(toward)
	aside = aside.normalized() if aside.length() > 0.0001 else Vector3.UP
	var joint: Vector3 = from + toward * first * cos_at + aside * first * sqrt(1.0 - cos_at * cos_at)
	var tip: Vector3 = from + toward * far
	_aim(upper, from, joint)
	var turned: Quaternion = _aim(lower, joint, tip)
	var end_rest: Basis = (_rest[end] as Transform3D).basis
	var end_basis: Basis = Basis(Quaternion.IDENTITY.slerp(turned, follow)) * end_rest
	skeleton.set_bone_global_pose(_bone[end], Transform3D(end_basis, tip))


## Put a bone at `from`, pointing at `to`, turned from its rest pose by the shortest way.
func _aim(bone: String, from: Vector3, to: Vector3) -> Quaternion:
	var turned := Quaternion(_along[bone] as Vector3, (to - from).normalized())
	skeleton.set_bone_global_pose(_bone[bone], Transform3D(Basis(turned) * (_rest[bone] as Transform3D).basis, from))
	return turned
