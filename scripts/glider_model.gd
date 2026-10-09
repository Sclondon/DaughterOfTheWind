extends Node3D
## What the glider looks like, and the girl who flies it.
##
## The glider: a flat wing made of panels with short round tips that hook back, in a matte cream
## eggshell finish. Its body is a squashed teardrop with both ends cut off, so it is an open tube
## with the jet inside. A thin fin stands on the seam under each wingtip, two low hoops with a
## strap between them are there to hold on to, and a few small electronics housings sit on top.
## The only parts that move are the rear flaps: together for pitch, opposite for roll.
##
## The girl (girl.gd) stands on the body holding the hoops. Flying level she stands, bent
## forward over her hands; in a climb she crouches down; when the glider drops away under her
## she hangs on with her legs trailing. Her short hair and her scarf are both small cloths that
## flap in the wind (hair.gd).
##
## It also owns the jet flame and the two wingtip vapour trails. Each trail is as strong as the
## lift its own tip is making, so the tip on the outside of a turn or on the down-going side of a
## roll streams first, and both stream at speed.

const MeshKit := preload("res://scripts/mesh_kit.gd")
const Trail := preload("res://scripts/trail.gd")
const Toon := preload("res://scripts/toon.gd")
const Hair := preload("res://scripts/hair.gd")
const Girl := preload("res://scripts/girl.gd")

## Where the body ends and the wing panels begin, where the round tips join on, and how long they are.
const ROOT := 0.3
const TIP_HINGE := 1.98
const TIP_LENGTH := 0.66
## How far the very end of the tip is swept back.
const HOOK := 0.36
## Leading and trailing edge of the wing (forward is -Z), and where the flap hinges.
const LEAD := -0.62
const TRAIL_EDGE := 0.58
const FLAP_HINGE := 0.06
const THICK := 0.12
## The top of the body, where she stands, and the top of the hoops, where she holds on.
const DECK := 0.19
const GRIP := Vector3(0.2, 0.55, -0.42)
const CREAM := Color(0.9, 0.84, 0.7)

var glider: Node3D
var girl: Node3D

var _flame: MeshInstance3D
var _halves: Array = []  # per side: [flap, tip, trail, side sign]
var _tip_last: Array = [Vector3.ZERO, Vector3.ZERO]
var _tip_strength: Array = [0.0, 0.0]
var _flame_size := 0.0
var _time := 0.0
# How much she is crouching and how much she is hanging on, 0..1 each. Neither means standing.
var _crouch := 0.0
var _dangle := 0.0


func _ready() -> void:
	var shell: ShaderMaterial = Toon.eggshell(CREAM)
	var dark: ShaderMaterial = Toon.paint(Color(0.13, 0.13, 0.15))
	var strap: ShaderMaterial = Toon.paint(Color(0.5, 0.26, 0.14))

	for side: float in [-1.0, 1.0]:
		_build_half(side, shell)
	_build_body(shell, dark)

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
	# The cone's point trails behind (+Z); its base sits in the tail of the body.
	_flame.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 1.2))
	_flame.visible = false
	add_child(_flame)

	# The two low hoops to hold on to, each an arch over the front of the body, and the strap
	# slung between their tops.
	for side: float in [-1.0, 1.0]:
		var foot_front := Vector3(0.21 * side, 0.12, -0.66)
		var top_front := Vector3(GRIP.x * side, GRIP.y, GRIP.z - 0.08)
		var top_back := Vector3(GRIP.x * side, GRIP.y, GRIP.z + 0.08)
		var foot_back := Vector3(0.21 * side, 0.13, -0.18)
		add_child(MeshKit.rod(foot_front, top_front, 0.024, shell))
		add_child(MeshKit.rod(top_front, top_back, 0.026, shell))
		add_child(MeshKit.rod(top_back, foot_back, 0.024, shell))
	add_child(MeshKit.rod(Vector3(-GRIP.x, GRIP.y, GRIP.z), Vector3(0, GRIP.y - 0.05, GRIP.z), 0.018, strap))
	add_child(MeshKit.rod(Vector3(0, GRIP.y - 0.05, GRIP.z), Vector3(GRIP.x, GRIP.y, GRIP.z), 0.018, strap))

	_build_electronics(dark)
	_build_girl()


## One half of the wing: the fixed front panel, the flap fitted close behind it, the round tip,
## and the fin on the seam where the tip joins on.
func _build_half(side: float, shell: Material) -> void:
	var front := MeshInstance3D.new()
	front.mesh = MeshKit.slab(_stations(ROOT * 0.6, TIP_HINGE - 0.005, side, 6),
			func(_x: float) -> Vector2: return Vector2(LEAD, FLAP_HINGE - 0.006), THICK)
	front.material_override = shell
	add_child(front)

	# The flap runs the whole length of the panel and sits tight against it.
	var flap := MeshInstance3D.new()
	flap.mesh = MeshKit.slab(_stations(ROOT * 0.6 + 0.012, TIP_HINGE - 0.02, side, 6),
			func(_x: float) -> Vector2: return Vector2(0.0, TRAIL_EDGE - FLAP_HINGE - 0.006), THICK * 0.94)
	flap.material_override = shell
	flap.position = Vector3(0, 0, FLAP_HINGE + 0.006)
	add_child(flap)

	# The tip: half an ellipse in outline with its end hooked back. It is fixed.
	var tip := Node3D.new()
	tip.position = Vector3(TIP_HINGE * side, 0, 0)
	add_child(tip)
	var xs := PackedFloat32Array()
	for i in 13:
		xs.append(TIP_LENGTH * sin(float(i) / 12.0 * PI * 0.5) * side)
	if side < 0.0:
		xs.reverse()
	var mid: float = (LEAD + TRAIL_EDGE) * 0.5
	var reach: float = (TRAIL_EDGE - LEAD) * 0.5
	var tip_mesh := MeshInstance3D.new()
	tip_mesh.mesh = MeshKit.slab(xs, func(x: float) -> Vector2:
		var out: float = absf(x) / TIP_LENGTH
		var w: float = sqrt(maxf(1.0 - out * out, 0.0))
		# Round, but with the end drawn back into a hook: the leading edge sweeps back furthest.
		var back: float = HOOK * out * out
		return Vector2(mid - reach * w + back * 1.5, mid + reach * w + back * 0.9), THICK, 8)
	tip_mesh.material_override = shell
	tip.add_child(tip_mesh)

	# The fin: a thin blade standing in the plane of the seam itself, rooted in the front of the
	# wing there and raked forward and down past the leading edge.
	var blade_long: float = 0.46
	var fin := MeshInstance3D.new()
	fin.mesh = MeshKit.slab(PackedFloat32Array([0.0, 0.08, 0.17, 0.27, 0.37, blade_long]),
			func(x: float) -> Vector2:
				var half: float = 0.11 * (1.0 - pow(x / blade_long, 1.6)) + 0.01
				return Vector2(-half, half), 0.04, 4)
	fin.material_override = shell
	# The slab runs along its own X: lay that along the rake, with its thin side across the span.
	var rake := Vector3(0, -0.45, -0.89).normalized()
	fin.transform = Transform3D(Basis(rake, Vector3.RIGHT, rake.cross(Vector3.RIGHT)),
			Vector3(TIP_HINGE * side, -0.02, LEAD + 0.14))
	add_child(fin)

	var trail: MeshInstance3D = Trail.new()
	trail.source = tip
	trail.offset = Vector3(TIP_LENGTH * 0.96 * side, 0, mid + HOOK * 1.15)
	add_child(trail)
	_halves.append([flap, tip, trail, side])


## Section positions for a panel on one side, always in ascending X as MeshKit.slab wants.
func _stations(from: float, to: float, side: float, count: int) -> PackedFloat32Array:
	var xs := PackedFloat32Array()
	for i in count + 1:
		xs.append(lerpf(from, to, float(i) / float(count)) * side)
	if side < 0.0:
		xs.reverse()
	return xs


## The body: a squashed teardrop with its nose and its tail cut off square, leaving a tube that
## is open at both ends (a wide mouth in front, the jet's narrow one behind).
func _build_body(shell: Material, dark: Material) -> void:
	var half := Vector2(0.43, DECK)
	var teardrop := func(t: float) -> Vector3:
		# Only the middle of the whole teardrop: from a little way in at the nose to most of the
		# way down the tail.
		var u: float = lerpf(0.12, 0.86, t)
		var r: float = pow(sin(PI * pow(u, 0.6)), 0.75) * lerpf(1.0, 0.75, u)
		return Vector3(half.x * r, half.y * r, 0.0)
	var long: float = 2.25
	var body := MeshInstance3D.new()
	body.mesh = MeshKit.body(long, teardrop, 20, 20, 2.3)
	body.material_override = shell
	body.position = Vector3(0, 0, -0.05)
	add_child(body)
	# Dark inside both cut ends, leaving a rim of shell, so they read as openings.
	for t: float in [0.0, 1.0]:
		var rim: Vector3 = teardrop.call(t)
		var hole := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 1.0
		disc.bottom_radius = 1.0
		disc.height = 0.012
		disc.radial_segments = 20
		hole.mesh = disc
		hole.material_override = dark
		hole.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(rim.x * 0.84, rim.y * 0.8, 1.0)),
				Vector3(0, 0, -0.05 + (t - 0.5) * long + (0.004 if t > 0.5 else -0.004)))
		add_child(hole)


## A few small electronics housings: low boxes with a lamp or two, a dome, an aerial and a run
## of conduit. Just enough to say there is something working inside.
func _build_electronics(dark: Material) -> void:
	var casing: ShaderMaterial = Toon.paint(Color(0.62, 0.6, 0.55))
	var brass: ShaderMaterial = Toon.shiny(Color(0.72, 0.56, 0.24))
	var red: ShaderMaterial = Toon.glowing(Color(0.9, 0.2, 0.15), Color(1.6, 0.25, 0.15))
	var green: ShaderMaterial = Toon.glowing(Color(0.3, 0.9, 0.5), Color(0.3, 1.4, 0.6))
	# [where, size] of each box.
	for box: Array in [
			[Vector3(0, DECK - 0.01, -0.86), Vector3(0.22, 0.07, 0.2)],
			[Vector3(0.24, DECK - 0.06, 0.66), Vector3(0.12, 0.06, 0.2)],
			[Vector3(-0.78, THICK * 0.5, -0.3), Vector3(0.26, 0.05, 0.18)],
			[Vector3(1.22, THICK * 0.5, -0.36), Vector3(0.18, 0.045, 0.24)],
			[Vector3(-1.5, THICK * 0.5, -0.12), Vector3(0.12, 0.04, 0.12)]]:
		var housing := MeshInstance3D.new()
		var shape := BoxMesh.new()
		shape.size = box[1]
		housing.mesh = shape
		housing.material_override = casing
		housing.position = box[0]
		add_child(housing)
	# Lamps on the nose box, and one on the far wing.
	var lamp := SphereMesh.new()
	lamp.radius = 0.018
	lamp.height = 0.036
	lamp.radial_segments = 8
	lamp.rings = 4
	for spot: Array in [[Vector3(-0.06, DECK + 0.03, -0.9), red], [Vector3(0.06, DECK + 0.03, -0.9), green],
			[Vector3(1.22, THICK * 0.5 + 0.03, -0.42), green]]:
		var light := MeshInstance3D.new()
		light.mesh = lamp
		light.material_override = spot[1]
		light.position = spot[0]
		add_child(light)
	# A brass dome behind where she stands, an aerial on the nose box, and conduit along the body.
	var dome := MeshInstance3D.new()
	var cap := SphereMesh.new()
	cap.radius = 0.07
	cap.height = 0.07
	cap.is_hemisphere = true
	cap.radial_segments = 12
	cap.rings = 5
	dome.mesh = cap
	dome.material_override = brass
	dome.position = Vector3(-0.2, DECK - 0.07, 0.72)
	add_child(dome)
	add_child(MeshKit.rod(Vector3(0.08, DECK + 0.02, -0.8), Vector3(0.1, DECK + 0.36, -0.7), 0.006, dark))
	add_child(MeshKit.rod(Vector3(0.33, 0.11, -0.7), Vector3(0.33, 0.1, 0.5), 0.014, dark))
	add_child(MeshKit.rod(Vector3(-0.78, THICK * 0.5 + 0.01, -0.2), Vector3(-0.36, THICK * 0.5 + 0.01, -0.2), 0.01, dark))


func _build_girl() -> void:
	girl = Girl.new()
	add_child(girl)
	# Her short hair, pinned across the back of her head. (Her head's "back" is the skeleton's -Z.)
	var hair: MeshInstance3D = Hair.new()
	hair.anchor = girl.head_anchor
	hair.root = girl.in_bone("head", Vector3(0, 0.07, -0.1))
	hair.across = girl.in_bone("head", Vector3.RIGHT)
	hair.link = 0.026
	hair.width = 0.21
	hair.end_width = 0.3
	hair.color = Girl.COLOURS["hair"]
	add_child(hair)
	# Her scarf: knotted at the back of her neck, streaming out behind.
	var scarf: MeshInstance3D = Hair.new()
	scarf.anchor = girl.chest_anchor
	scarf.root = girl.in_bone("chest", Vector3(0, 0.15, -0.07))
	scarf.across = girl.in_bone("chest", Vector3.RIGHT)
	scarf.link = 0.11
	scarf.width = 0.12
	scarf.end_width = 0.26
	scarf.color = Color(0.82, 0.22, 0.18)
	add_child(scarf)
	# The scarf wound round her neck.
	var wrap := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.045
	ring.outer_radius = 0.085
	ring.rings = 14
	ring.ring_segments = 8
	wrap.mesh = ring
	wrap.material_override = Toon.paint(Color(0.82, 0.22, 0.18))
	girl.chest_anchor.add_child(wrap)
	wrap.transform = Transform3D(Basis(Quaternion(Vector3.UP, girl.in_bone("chest", Vector3.UP).normalized())),
			girl.in_bone("chest", Vector3(0, 0.16, 0.0)))


func _process(delta: float) -> void:
	if glider == null:
		return
	_time += delta
	var blend: float = 1.0 - exp(-10.0 * delta)
	var stick: Vector2 = glider.control

	_pose_girl(delta)

	_flame_size = lerpf(_flame_size, 1.0 if glider.boosting else 0.0, 1.0 - exp(-12.0 * delta))
	_flame.visible = _flame_size > 0.02
	if _flame.visible:
		var flick: float = 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.05)
		_flame.scale = Vector3(1.0, 2.4 * _flame_size * flick, 1.0)
		_flame.position.z = 1.05 + 1.2 * _flame_size * flick

	var body: Transform3D = glider.get_global_transform_interpolated()
	for i in _halves.size():
		var flap: Node3D = _halves[i][0]
		var tip: Node3D = _halves[i][1]
		var trail: MeshInstance3D = _halves[i][2]
		var side: float = _halves[i][3]

		# Rolling right lifts the right flap and drops the left; pulling up lifts both.
		# (Turning about +X swings a trailing edge down, so "up" is a negative angle.)
		var deflect: float = clampf(stick.y * 0.42 + stick.x * side * 0.5, -0.65, 0.65)
		flap.rotation.x = lerpf(flap.rotation.x, -deflect, blend)

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


## Stand, crouch or hang on, by how the glider is moving, and pose her for it.
func _pose_girl(delta: float) -> void:
	# Climbing (or hauling back on the stick) she crouches; when it falls away she hangs on.
	var climb: float = glider.climb
	var want_crouch: float = maxf(smoothstep(2.5, 9.0, climb), smoothstep(0.35, 0.9, glider.control.y))
	var want_dangle: float = smoothstep(-6.0, -15.0, climb) * (1.0 - want_crouch)
	var settle: float = 1.0 - exp(-4.5 * delta)
	_crouch = lerpf(_crouch, want_crouch, settle)
	_dangle = lerpf(_dangle, want_dangle, settle)
	var stand: float = clampf(1.0 - _crouch - _dangle, 0.0, 1.0)

	# The three poses, as where her hips are and how far forward she is bent (radians):
	#   standing  legs nearly straight, bent well forward over her hands
	#   crouched  hips down close to her heels, more upright
	#   hanging   hips up and back off the deck, body stretched out flat behind her arms
	var hips: Vector3 = Vector3(0, 0.93, 0.03) * stand + Vector3(0, 0.6, 0.16) * _crouch + Vector3(0, 0.88, 0.28) * _dangle
	var lean: float = 1.15 * stand + 0.85 * _crouch + 1.42 * _dangle
	# She leans into a turn a little.
	var bank: float = atan2(-glider.basis.x.y, glider.basis.y.y)
	var roll: float = clampf(bank * 0.12, -0.2, 0.2)

	var hands: Array = []
	var feet: Array = []
	# Her left is the glider's -X, and pose() wants [left, right].
	for side: float in [-1.0, 1.0]:
		# Her wrists sit just behind and above the bar her fingers are round.
		hands.append(Vector3(GRIP.x * side, GRIP.y + 0.05, GRIP.z + 0.06))
		# On the deck when standing or crouched; trailing out behind, swinging, when she hangs.
		var planted := Vector3(0.11 * side, DECK + 0.08, 0.02 + _crouch * 0.1)
		var swing: float = sin(_time * 5.0 + side * 1.3)
		var trailing := Vector3(0.13 * side + swing * 0.04, 0.42 + swing * 0.09, 0.98)
		feet.append(planted.lerp(trailing, _dangle))
	girl.pose(hips, lean, roll, hands, feet, _dangle)
