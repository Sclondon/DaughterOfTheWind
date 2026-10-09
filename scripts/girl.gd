extends Node3D
## The pilot: the girl built in Blender (art/build_girl.py -> models/girl.glb), one continuous
## skinned mesh on a skeleton, painted there with vertex colours (her clothes, kit, goggles and
## gas mask). This script gives her the cel shader, dresses her in the things that move, and
## poses her.
##
## What moves is made here, not in Blender: her hair, a shaggy mop of chunky locks (locks.gd),
## and two pieces of cloth (hair.gd), the scarf streaming from the back of her neck and the
## skirt of her tunic, which hangs from her belt, flaps, and is kept outside her legs.
##
## She is not animated from clips. Each frame the glider's model says where her hips are, how far
## she is bent forward, and where her hands and feet should be, and pose() works the skeleton
## out from that: the spine follows the hips, the head stays looking ahead, and each arm and leg
## is bent at the elbow or knee by just enough to reach (two-bone IK). So her hands stay on the
## handles and her feet on the deck whatever she does in between. Her hands are fists already
## closed round a bar (they are modelled that way), and pose() turns each one so that the bar
## inside its fingers is the handle.
##
## Everything passed to pose() is in this node's own space, which is the glider's: forward is
## -Z, up is +Y, her right hand is +X.

const Toon := preload("res://scripts/toon.gd")
const Hair := preload("res://scripts/hair.gd")
const Locks := preload("res://scripts/locks.gd")
const Model := preload("res://models/girl.glb")

## Colours the game needs to match hers (the rest are painted on the model in Blender).
const HAIR := Color(0.58, 0.27, 0.13)
const LENS := Color(0.5, 0.78, 0.82)
const TUNIC := Color(0.2, 0.42, 0.8)
const TRIM := Color(0.95, 0.91, 0.8)
const SCARF := Color(0.82, 0.22, 0.18)
## Where the middle of the bar inside her left fist is from her wrist, in the T pose: out along
## her arm, and down into her palm (art/build_girl.py: GRIP less the wrist).
const FIST := Vector2(0.093, 0.046)
## How far her hand is turned down from level, round the bar, when she holds on (radians).
const HAND_TILT := 0.75

var skeleton: Skeleton3D
## Nodes that ride on her head and on her chest, for the hair and the scarf to be pinned to.
var head_anchor: BoneAttachment3D
var chest_anchor: BoneAttachment3D
var hips_anchor: BoneAttachment3D

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
	# Two materials come in from Blender: "body", which is all vertex paint, and "glass", her
	# goggle lenses.
	for surface in mesh.mesh.get_surface_count():
		var material: Material = mesh.mesh.surface_get_material(surface)
		var glass: bool = material != null and material.resource_name == "glass"
		mesh.set_surface_override_material(surface, Toon.shiny(LENS, LENS * 0.25) if glass else Toon.painted())
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
	hips_anchor = BoneAttachment3D.new()
	skeleton.add_child(hips_anchor)
	hips_anchor.bone_name = "hips"
	_dress()


## Her hair, her scarf and her skirt.
func _dress() -> void:
	var hair: Node3D = Locks.new()
	hair.anchor = head_anchor
	hair.frame = (_rest["head"] as Transform3D).affine_inverse()
	hair.color = HAIR
	add_child(hair)

	# Her scarf: wound round her neck, the loose end streaming out behind.
	var scarf: MeshInstance3D = Hair.new()
	scarf.anchor = chest_anchor
	scarf.root = in_bone("chest", Vector3(0, 0.15, -0.07))
	scarf.across = in_bone("chest", Vector3.RIGHT)
	scarf.strands = 5
	scarf.links = 14
	scarf.link = 0.09
	scarf.width = 0.11
	scarf.end_width = 0.24
	scarf.flutter = 0.4
	scarf.color = SCARF
	add_child(scarf)
	var wrap := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.045
	ring.outer_radius = 0.085
	ring.rings = 24
	ring.ring_segments = 12
	wrap.mesh = ring
	wrap.material_override = Toon.paint(SCARF)
	chest_anchor.add_child(wrap)
	wrap.transform = Transform3D(Basis(Quaternion(Vector3.UP, in_bone("chest", Vector3.UP).normalized())),
			in_bone("chest", Vector3(0, 0.16, 0.0)))

	# The skirt of her tunic: a ring of cloth hung from just under her belt, flaring to the hem.
	var skirt: MeshInstance3D = Hair.new()
	skirt.anchor = hips_anchor
	var hung: Array = []
	for k in 18:
		var turn: float = TAU * float(k) / 18.0
		var round_her := Vector3(cos(turn), 0.0, sin(turn))
		hung.append([in_bone("hips", round_her * Vector3(0.106, 0, 0.09) + Vector3(0, 0.06, 0)),
				in_bone("hips", round_her * 0.4 + Vector3.DOWN)])
	skirt.shape = hung
	skirt.closed = true
	skirt.links = 6
	skirt.link = 0.047
	# It is in the lee of her body, so the wind only tugs at it, and it is heavy enough to hang:
	# bent over the handles, the back of it drapes over her seat and the front lies in her lap.
	skirt.stiff = 45.0
	skirt.drag = 0.3
	skirt.weight = 9.0
	skirt.flutter = 0.1
	# The paint on her body is used by the shader as it is written, so hand these over the same
	# way and the skirt matches the tunic it hangs from.
	skirt.color = TUNIC.linear_to_srgb()
	skirt.hem = 1
	skirt.hem_color = TRIM.linear_to_srgb()
	skirt.solids = _legs
	add_child(skirt)


## Her legs and seat as capsules in world space, for the skirt to stay outside of.
func _legs() -> Array:
	var world: Transform3D = skeleton.get_global_transform_interpolated()
	var holds: Array = []
	for side: String in ["L", "R"]:
		var hip: Vector3 = world * skeleton.get_bone_global_pose(_bone["thigh_" + side]).origin
		var knee: Vector3 = world * skeleton.get_bone_global_pose(_bone["shin_" + side]).origin
		var ankle: Vector3 = world * skeleton.get_bone_global_pose(_bone["foot_" + side]).origin
		holds.append([hip, knee, 0.082])
		holds.append([knee, ankle, 0.066])
	var seat: Vector3 = world * skeleton.get_bone_global_pose(_bone["hips"]).origin
	var ribs: Vector3 = world * skeleton.get_bone_global_pose(_bone["chest"]).origin
	holds.append([seat + (seat - ribs).normalized() * 0.02, ribs, 0.098])
	return holds


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
## (radians) and `roll` how far tipped to her right; `hands` are the two places on the handles
## (bars running fore and aft) that her fists close round, and `feet` where her ankles should be
## ([left, right]); `loose` (0..1) lets her feet hang from the shins instead of standing flat.
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
		# Her hand lies over the top of the bar, turned down round it toward the outside, so the
		# fingers go over and under it. That fixes where the wrist is: up and a little inboard.
		var turned := Basis(Vector3.BACK, -HAND_TILT * outward.x)
		var wrist: Vector3 = into * (hands[i] as Vector3) - turned * Vector3(FIST.x * outward.x, -FIST.y, 0.0)
		# Elbows point out and back, and a little down.
		_reach("upper_arm_" + side, "forearm_" + side, "hand_" + side, shoulder, wrist,
				Vector3(0, -0.5, -0.7) + outward * 0.8, 1.0, turned * (_rest["hand_" + side] as Transform3D).basis)
		var hip: Vector3 = carried * (_rest["thigh_" + side] as Transform3D).origin
		# Knees point forward and a little out.
		_reach("thigh_" + side, "shin_" + side, "foot_" + side, hip, into * (feet[i] as Vector3),
				Vector3(0, 0.25, 1.0) + outward * 0.25, loose)


## Bend a limb of two bones so that its end reaches a target (as nearly as its length allows),
## with the joint pushed out toward `pole`. `follow` (0..1) is how much the end bone (hand or
## foot) turns with the lower bone instead of keeping its rest angle.
## Give `held` to set the end bone's facing outright (a hand on a handle).
func _reach(upper: String, lower: String, end: String, from: Vector3, to: Vector3, pole: Vector3, follow: float, held: Variant = null) -> void:
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
	if held != null:
		end_basis = held
	skeleton.set_bone_global_pose(_bone[end], Transform3D(end_basis, tip))


## Put a bone at `from`, pointing at `to`, turned from its rest pose by the shortest way.
func _aim(bone: String, from: Vector3, to: Vector3) -> Quaternion:
	var turned := Quaternion(_along[bone] as Vector3, (to - from).normalized())
	skeleton.set_bone_global_pose(_bone[bone], Transform3D(Basis(turned) * (_rest[bone] as Transform3D).basis, from))
	return turned
