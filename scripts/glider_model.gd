extends Node3D
## What the glider looks like: a flat white wing made of panels with big round tips, a teardrop
## pod in the middle with a jet in its tail, two hoops with a strap between them to hold on to,
## and a small pilot in blue lying along the top. All of it is built here from MeshKit shapes.
##
## The wing is in separate pieces so it can move with the flying:
##   - each side's rear flap swings up or down with the stick (both for pitch, opposite for roll)
##   - each round tip twists with the roll and bends up when the wing is loaded in a turn or pull-up
##   - the whole wing half flexes a little with the load
## It also owns the jet flame and the two wingtip vapour trails. Each trail is as strong as the
## lift its own tip is making, so the tip on the outside of a turn or on the down-going side of a
## roll streams first, and both stream at speed.

const MeshKit := preload("res://scripts/mesh_kit.gd")
const Trail := preload("res://scripts/trail.gd")

## Where the pod ends and the wing panels begin, where the round tips hinge on, and how long they are.
const ROOT := 0.3
const TIP_HINGE := 1.98
const TIP_LENGTH := 1.0
## Leading and trailing edge of the wing (forward is -Z), and where the flap hinges.
const LEAD := -0.62
const TRAIL_EDGE := 0.58
const FLAP_HINGE := 0.06
const THICK := 0.12

var glider: Node3D

var _pilot: Node3D
var _flame: MeshInstance3D
var _halves: Array = []  # per side: [wing half, flap, tip, trail, side sign]
var _tip_last: Array = [Vector3.ZERO, Vector3.ZERO]
var _tip_strength: Array = [0.0, 0.0]
var _flame_size := 0.0


func _ready() -> void:
	var white := _paint(Color(0.97, 0.97, 0.94), 0.5)
	var cream := _paint(Color(0.9, 0.89, 0.84), 0.6)
	var dark := _paint(Color(0.16, 0.17, 0.2), 0.5)
	var strap := _paint(Color(0.5, 0.26, 0.14), 0.8)
	var red := _paint(Color(0.75, 0.16, 0.12), 0.6)

	for side: float in [-1.0, 1.0]:
		_build_half(side, white)

	# The pod: a flattened teardrop, blunt at the nose and drawn out to the jet at the tail.
	var pod := MeshInstance3D.new()
	pod.mesh = MeshKit.body(2.5, _pod_shape, 16, 18, 2.3)
	pod.material_override = white
	pod.position = Vector3(0, 0.03, -0.05)
	add_child(pod)
	add_child(MeshKit.rod(Vector3(0, 0.04, 1.08), Vector3(0, 0.04, 1.26), 0.1, dark))
	add_child(MeshKit.rod(Vector3(-0.2, 0.17, -0.78), Vector3(-0.2, 0.2, -0.62), 0.03, red))

	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flame_mat.albedo_color = Color(1.0, 0.75, 0.4, 0.9)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.1
	cone.height = 1.0
	cone.radial_segments = 10
	_flame = MeshInstance3D.new()
	_flame.mesh = cone
	_flame.material_override = flame_mat
	# The cone's point trails behind (+Z); its base sits in the nozzle.
	_flame.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.04, 1.35))
	_flame.visible = false
	add_child(_flame)

	# The two hoops to hold on to, each an arch from the front of the pod to its middle, and the
	# strap slung between their tops.
	for side: float in [-1.0, 1.0]:
		var foot_front := Vector3(0.19 * side, 0.16, -0.5)
		var top_front := Vector3(0.21 * side, 0.74, -0.2)
		var top_back := Vector3(0.21 * side, 0.76, -0.02)
		var foot_back := Vector3(0.2 * side, 0.18, 0.22)
		add_child(MeshKit.rod(foot_front, top_front, 0.026, cream))
		add_child(MeshKit.rod(top_front, top_back, 0.026, cream))
		add_child(MeshKit.rod(top_back, foot_back, 0.026, cream))
	add_child(MeshKit.rod(Vector3(-0.21, 0.74, -0.11), Vector3(0, 0.68, -0.11), 0.022, strap))
	add_child(MeshKit.rod(Vector3(0, 0.68, -0.11), Vector3(0.21, 0.74, -0.11), 0.022, strap))

	_build_pilot()


## One half of the wing: the fixed front panel, the flap behind it, the round tip, and the small
## fin where the tip joins on.
func _build_half(side: float, white: Material) -> void:
	var half := Node3D.new()
	add_child(half)

	var front := MeshInstance3D.new()
	front.mesh = MeshKit.slab(_stations(ROOT * 0.6, TIP_HINGE - 0.02, side, 6),
			func(_x: float) -> Vector2: return Vector2(LEAD, FLAP_HINGE - 0.02), THICK)
	front.material_override = white
	half.add_child(front)

	var flap := MeshInstance3D.new()
	flap.mesh = MeshKit.slab(_stations(ROOT + 0.06, TIP_HINGE - 0.08, side, 6),
			func(_x: float) -> Vector2: return Vector2(0.0, TRAIL_EDGE - FLAP_HINGE), THICK * 0.72)
	flap.material_override = white
	flap.position = Vector3(0, -0.005, FLAP_HINGE)
	half.add_child(flap)

	# The tip: half an ellipse in outline, hinged along the end of the panels.
	var tip := Node3D.new()
	tip.position = Vector3(TIP_HINGE * side, 0, 0)
	half.add_child(tip)
	var xs := PackedFloat32Array()
	for i in 13:
		xs.append(TIP_LENGTH * sin(float(i) / 12.0 * PI * 0.5) * side)
	if side < 0.0:
		xs.reverse()
	var mid: float = (LEAD + TRAIL_EDGE) * 0.5
	var reach: float = (TRAIL_EDGE - LEAD) * 0.5
	var tip_mesh := MeshInstance3D.new()
	tip_mesh.mesh = MeshKit.slab(xs, func(x: float) -> Vector2:
		var w: float = sqrt(maxf(1.0 - pow(absf(x) / TIP_LENGTH, 2.0), 0.0))
		return Vector2(mid - reach * w, mid + reach * w), THICK, 8)
	tip_mesh.material_override = white
	tip.add_child(tip_mesh)

	# The fin under the joint: a small blade raked forward and down.
	var fin := MeshInstance3D.new()
	fin.mesh = MeshKit.slab(PackedFloat32Array([0.0, 0.07, 0.16, 0.26, 0.36, 0.44]),
			func(x: float) -> Vector2: return Vector2(-0.34 + x * 0.5, 0.1 - x * 0.3), 0.045, 4)
	fin.material_override = white
	# The slab runs along +X; stand it on end so it hangs down, then rake it.
	fin.transform = Transform3D(Basis(Vector3.RIGHT, -0.5) * Basis(Vector3.BACK, -PI * 0.5),
			Vector3((TIP_HINGE - 0.03) * side, -0.02, LEAD + 0.42))
	half.add_child(fin)

	var trail: MeshInstance3D = Trail.new()
	trail.source = tip
	trail.offset = Vector3(TIP_LENGTH * 0.97 * side, 0, mid + 0.1)
	add_child(trail)
	_halves.append([half, flap, tip, trail, side])


## Section positions for a panel on one side, always in ascending X as MeshKit.slab wants.
func _stations(from: float, to: float, side: float, count: int) -> PackedFloat32Array:
	var xs := PackedFloat32Array()
	for i in count + 1:
		xs.append(lerpf(from, to, float(i) / float(count)) * side)
	if side < 0.0:
		xs.reverse()
	return xs


func _pod_shape(t: float) -> Vector3:
	# Widest a third of the way back; the nose is blunt, the tail long.
	var r: float = pow(sin(PI * pow(t, 0.6)), 0.75)
	r = maxf(r, 0.03) * lerpf(1.0, 0.75, t)
	return Vector3(0.33 * r, 0.21 * r, 0.0)


func _build_pilot() -> void:
	var tunic := _paint(Color(0.2, 0.42, 0.78), 0.8)
	var skin := _paint(Color(0.95, 0.78, 0.66), 0.8)
	var hair := _paint(Color(0.55, 0.27, 0.14), 0.7)
	var cloth := _paint(Color(0.93, 0.9, 0.82), 0.85)
	var boots := _paint(Color(0.45, 0.32, 0.22), 0.8)

	_pilot = Node3D.new()
	add_child(_pilot)
	# She lies along the pod behind the hoops, chest up on her arms, legs trailing.
	_pilot.add_child(MeshKit.rod(Vector3(0, 0.46, 0.12), Vector3(0, 0.36, 0.72), 0.15, tunic))
	var head := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.125
	ball.height = 0.25
	ball.radial_segments = 14
	ball.rings = 8
	head.mesh = ball
	head.material_override = skin
	head.position = Vector3(0, 0.62, -0.02)
	_pilot.add_child(head)
	var mop := MeshInstance3D.new()
	mop.mesh = ball
	mop.material_override = hair
	mop.scale = Vector3(1.1, 1.05, 1.1)
	mop.position = Vector3(0, 0.65, 0.03)
	_pilot.add_child(mop)
	for side: float in [-1.0, 1.0]:
		# Hands on the front legs of the hoops.
		_pilot.add_child(MeshKit.rod(Vector3(0.17 * side, 0.48, 0.12), Vector3(0.2 * side, 0.42, -0.34), 0.045, tunic))
		_pilot.add_child(MeshKit.rod(Vector3(0.09 * side, 0.36, 0.72), Vector3(0.11 * side, 0.3, 1.22), 0.07, cloth))
		_pilot.add_child(MeshKit.rod(Vector3(0.11 * side, 0.3, 1.22), Vector3(0.12 * side, 0.29, 1.54), 0.06, boots))


func _paint(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat


func _process(delta: float) -> void:
	if glider == null:
		return
	var blend: float = 1.0 - exp(-10.0 * delta)
	var stick: Vector2 = glider.control
	var pull: float = glider.load_factor

	# The pilot leans into the turn.
	var bank: float = atan2(-glider.basis.x.y, glider.basis.y.y)
	_pilot.rotation.z = lerpf(_pilot.rotation.z, clampf(-bank * 0.12, -0.2, 0.2), blend * 0.6)

	_flame_size = lerpf(_flame_size, 1.0 if glider.boosting else 0.0, 1.0 - exp(-12.0 * delta))
	_flame.visible = _flame_size > 0.02
	if _flame.visible:
		var flick: float = 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.05)
		_flame.scale = Vector3(1.0, 2.4 * _flame_size * flick, 1.0)
		_flame.position.z = 1.26 + 1.2 * _flame_size * flick

	var body: Transform3D = glider.get_global_transform_interpolated()
	for i in _halves.size():
		var half: Node3D = _halves[i][0]
		var flap: Node3D = _halves[i][1]
		var tip: Node3D = _halves[i][2]
		var trail: MeshInstance3D = _halves[i][3]
		var side: float = _halves[i][4]

		# Rolling right lifts the right flap and drops the left; pulling up lifts both.
		# (Turning about +X swings a trailing edge down, so "up" is a negative angle.)
		var deflect: float = clampf(stick.y * 0.42 + stick.x * side * 0.5, -0.65, 0.65)
		flap.rotation.x = lerpf(flap.rotation.x, -deflect, blend)
		# The tips warp the same way, and bend up under load.
		tip.rotation.x = lerpf(tip.rotation.x, -stick.x * side * 0.3, blend)
		var bend: float = clampf((pull - 1.0) * 0.09, -0.1, 0.24)
		tip.rotation.z = lerpf(tip.rotation.z, bend * side, blend * 0.6)
		half.rotation.z = lerpf(half.rotation.z, clampf((pull - 1.0) * 0.03, -0.03, 0.08) * side, blend * 0.6)

		# How hard is this tip working? Take its own speed through the air (the tip on the outside
		# of a turn moves faster, the one going down in a roll meets the air at a steeper angle)
		# and work out the lift it is making, the same way the flight model does for the whole wing.
		var at: Vector3 = tip.get_global_transform_interpolated() * (trail.offset as Vector3)
		var strength: float = 0.0
		if delta > 0.0 and _tip_last[i] != Vector3.ZERO:
			var v: Vector3 = (at - (_tip_last[i] as Vector3)) / delta
			var speed: float = v.length()
			if speed > 1.0 and speed < 400.0:
				var angle: float = atan2(-v.dot(body.basis.y), maxf(v.dot(-body.basis.z), 0.1))
				var lift: float = clampf(glider.CL0 + glider.CL_SLOPE * angle, 0.0, 1.6)
				var loading: float = glider.LIFT * speed * speed * lift / glider.GRAVITY
				strength = clampf((loading - 1.12) * 0.75, 0.0, 0.85) + smoothstep(38.0, 72.0, speed) * 0.5
				if glider.boosting:
					strength += 0.2
		_tip_last[i] = at
		_tip_strength[i] = lerpf(_tip_strength[i], clampf(strength, 0.0, 1.0), 1.0 - exp(-8.0 * delta))
		trail.strength = _tip_strength[i]
