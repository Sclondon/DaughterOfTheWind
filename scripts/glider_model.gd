extends Node3D
## What the glider looks like, and the girl who flies it.
##
## The glider: a wing made of flat panels, angled up very slightly from the body, with round
## tips that hook back and droop a little from where they join on, in a matte cream eggshell
## finish. Its body is a squashed teardrop with both ends cut off, so it is an open tube with the
## jet inside. Under each tip joint hangs a long pointed pod that sticks out past the trailing
## edge, two hooked skids under the body are its landing gear, two low hoops with a strap
## between them are there to hold on to, and a few small electronics housings are let into it.
## The only parts that move are the rear flaps: together for pitch, opposite for roll.
##
## The girl (girl.gd) stands on the body holding the hoops. Flying level she stands, bent
## forward over her hands; in a climb she crouches down; when the glider drops away under her
## she hangs on with her legs trailing. She brings her own hair, scarf and skirt, which all
## blow in the wind (girl.gd).
##
## It also owns the jet flame and the two wingtip vapour trails. Each trail is as strong as the
## lift its own tip is making, so the tip on the outside of a turn or on the down-going side of a
## roll streams first, and both stream at speed.

const MeshKit := preload("res://scripts/mesh_kit.gd")
const Trail := preload("res://scripts/trail.gd")
const Toon := preload("res://scripts/toon.gd")
const Girl := preload("res://scripts/girl.gd")

## Where the body ends and the wing panels begin, where the round tips join on, and how long they are.
const ROOT := 0.3
const TIP_HINGE := 2.3
const TIP_LENGTH := 0.86
## How far each wing is angled up from level, and how far each tip is angled back down from
## its wing at the joint (radians).
const DIHEDRAL := 0.07
const DROOP := 0.17
## How far the very end of the tip is swept back.
const HOOK := 0.36
## Leading and trailing edge of the wing (forward is -Z), and where the flap hinges.
const LEAD := -0.62
const TRAIL_EDGE := 0.58
const FLAP_HINGE := 0.06
const THICK := 0.12
## The top of the body, where she stands, and the top of the hoops, where she holds on.
const DECK := 0.19
const GRIP := Vector3(0.2, 0.37, -0.42)
const CREAM := Color(0.87, 0.78, 0.59)

var glider: Node3D
var girl: Node3D

var _flame: MeshInstance3D
var _halves: Array = []  # per side: [flap, tip, trail, side sign]
var _wings: Array = []  # the two wing halves (left, right), each tilted up by DIHEDRAL
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
	_build_skids(shell)

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
	# Everything on this side hangs off one node, tilted up from the body.
	var half := Node3D.new()
	half.rotation.z = DIHEDRAL * side
	add_child(half)
	_wings.append(half)
	var front := MeshInstance3D.new()
	front.mesh = MeshKit.slab(_stations(ROOT * 0.6, TIP_HINGE - 0.005, side, 6),
			func(_x: float) -> Vector2: return Vector2(LEAD, FLAP_HINGE - 0.006), THICK)
	front.material_override = shell
	half.add_child(front)

	# The flap runs the whole length of the panel and sits tight against it.
	var flap := MeshInstance3D.new()
	flap.mesh = MeshKit.slab(_stations(ROOT * 0.6 + 0.012, TIP_HINGE - 0.02, side, 6),
			func(_x: float) -> Vector2: return Vector2(0.0, TRAIL_EDGE - FLAP_HINGE - 0.006), THICK * 0.94)
	flap.material_override = shell
	flap.position = Vector3(0, 0, FLAP_HINGE + 0.006)
	half.add_child(flap)

	# The tip: half an ellipse in outline with its end hooked back, angled down from the joint.
	var tip := Node3D.new()
	tip.position = Vector3(TIP_HINGE * side, 0, 0)
	tip.rotation.z = -DROOP * side
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
		var out: float = absf(x) / TIP_LENGTH
		var w: float = sqrt(maxf(1.0 - out * out, 0.0))
		# Round, but with the end drawn back into a hook: the leading edge sweeps back furthest.
		var back: float = HOOK * out * out
		return Vector2(mid - reach * w + back * 1.5, mid + reach * w + back * 0.9), THICK, 8)
	tip_mesh.material_override = shell
	tip.add_child(tip_mesh)

	# Under the joint: a long pointed oval pod, running fore and aft, hanging off the back of the wing.
	var pod := MeshInstance3D.new()
	pod.mesh = MeshKit.body(1.6, func(t: float) -> Vector3:
		var r: float = maxf(pow(sin(PI * t), 0.7), 0.03)
		return Vector3(0.06 * r, 0.075 * r, 0.0), 10, 14)
	pod.material_override = shell
	pod.position = Vector3(TIP_HINGE * side, -THICK * 0.5 - 0.04, mid + 0.42)
	half.add_child(pod)

	var trail: MeshInstance3D = Trail.new()
	trail.source = tip
	trail.offset = Vector3(TIP_LENGTH * 0.96 * side, 0, mid + HOOK * 1.15)
	half.add_child(trail)
	_halves.append([flap, tip, trail, side])


## Section positions for a panel on one side, always in ascending X as MeshKit.slab wants.
func _stations(from: float, to: float, side: float, count: int) -> PackedFloat32Array:
	var xs := PackedFloat32Array()
	for i in count + 1:
		xs.append(lerpf(from, to, float(i) / float(count)) * side)
	if side < 0.0:
		xs.reverse()
	return xs


## Half the body's width and height at a share t of the way along it (0 the nose, 1 the tail).
## It is the middle of a teardrop: from a little way in at the nose to most of the way down the tail.
func _body_shape(t: float) -> Vector3:
	var u: float = lerpf(0.12, 0.86, t)
	var r: float = pow(sin(PI * pow(u, 0.6)), 0.75) * lerpf(1.0, 0.75, u)
	return Vector3(0.43 * r, DECK * r, 0.0)


const BODY_LONG := 2.25
const BODY_Z := -0.05


## How high the top of the body is at a given z.
func _deck_at(z: float) -> float:
	return _body_shape(clampf((z - BODY_Z) / BODY_LONG + 0.5, 0.0, 1.0)).y


## The body: a squashed teardrop with its nose and its tail cut off square, leaving a tube that
## is open at both ends (a wide mouth in front, the jet's narrow one behind).
func _build_body(shell: Material, dark: Material) -> void:
	var body := MeshInstance3D.new()
	body.mesh = MeshKit.body(BODY_LONG, _body_shape, 20, 20, 2.3)
	body.material_override = shell
	body.position = Vector3(0, 0, BODY_Z)
	add_child(body)
	# Dark inside both cut ends, leaving a rim of shell, so they read as openings.
	for t: float in [0.0, 1.0]:
		var rim: Vector3 = _body_shape(t)
		var hole := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 1.0
		disc.bottom_radius = 1.0
		disc.height = 0.012
		disc.radial_segments = 20
		hole.mesh = disc
		hole.material_override = dark
		hole.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(rim.x * 0.84, rim.y * 0.8, 1.0)),
				Vector3(0, 0, BODY_Z + (t - 0.5) * BODY_LONG + (0.004 if t > 0.5 else -0.004)))
		add_child(hole)


## The landing gear: two small hooked bars under the body, each a runner on two short legs
## with its front end curled up like the tip of a ski.
func _build_skids(shell: Material) -> void:
	for side: float in [-1.0, 1.0]:
		var x: float = 0.2 * side
		var low: float = -0.34
		add_child(MeshKit.rod(Vector3(x * 0.9, -0.1, -0.4), Vector3(x, low, -0.46), 0.016, shell))
		add_child(MeshKit.rod(Vector3(x * 0.9, -0.1, 0.36), Vector3(x, low, 0.42), 0.016, shell))
		add_child(MeshKit.rod(Vector3(x, low, -0.5), Vector3(x, low, 0.56), 0.018, shell))
		add_child(MeshKit.rod(Vector3(x, low, -0.5), Vector3(x, low + 0.05, -0.64), 0.018, shell))
		add_child(MeshKit.rod(Vector3(x, low + 0.05, -0.64), Vector3(x, low + 0.15, -0.71), 0.017, shell))


## A few small electronics housings, each let into the surface it sits on (the body's top, or a
## wing panel): low boxes with a lamp or two, a dome, an aerial, a run of conduit.
func _build_electronics(dark: Material) -> void:
	var casing: ShaderMaterial = Toon.paint(Color(0.62, 0.6, 0.55))
	var brass: ShaderMaterial = Toon.shiny(Color(0.72, 0.56, 0.24))
	var red: ShaderMaterial = Toon.glowing(Color(0.9, 0.2, 0.15), Color(1.6, 0.25, 0.15))
	var green: ShaderMaterial = Toon.glowing(Color(0.3, 0.9, 0.5), Color(0.3, 1.4, 0.6))
	var lamp := SphereMesh.new()
	lamp.radius = 0.018
	lamp.height = 0.036
	lamp.radial_segments = 8
	lamp.rings = 4

	# A box sunk into a surface whose top is at `top`: a third of it shows.
	var housing := func(parent: Node3D, x: float, top: float, z: float, size: Vector3, light: Material) -> void:
		var box := MeshInstance3D.new()
		var shape := BoxMesh.new()
		shape.size = size
		box.mesh = shape
		box.material_override = casing
		box.position = Vector3(x, top - size.y * 0.18, z)
		parent.add_child(box)
		if light:
			var bulb := MeshInstance3D.new()
			bulb.mesh = lamp
			bulb.material_override = light
			bulb.position = Vector3(x + size.x * 0.25, top + size.y * 0.34, z - size.z * 0.2)
			parent.add_child(bulb)

	# On the body: one on the nose with two lamps and the aerial, one behind where she stands.
	var nose_z: float = -0.82
	housing.call(self, 0.0, _deck_at(nose_z), nose_z, Vector3(0.22, 0.07, 0.18), green)
	var second := MeshInstance3D.new()
	second.mesh = lamp
	second.material_override = red
	second.position = Vector3(-0.055, _deck_at(nose_z) + 0.024, nose_z - 0.036)
	add_child(second)
	add_child(MeshKit.rod(Vector3(0.07, _deck_at(nose_z), nose_z + 0.05), Vector3(0.09, _deck_at(nose_z) + 0.34, nose_z + 0.14), 0.006, dark))
	housing.call(self, 0.1, _deck_at(0.66), 0.66, Vector3(0.12, 0.06, 0.18), null)
	var dome := MeshInstance3D.new()
	var cap := SphereMesh.new()
	cap.radius = 0.06
	cap.height = 0.06
	cap.is_hemisphere = true
	cap.radial_segments = 12
	cap.rings = 5
	dome.mesh = cap
	dome.material_override = brass
	dome.position = Vector3(-0.1, _deck_at(0.74) - 0.012, 0.74)
	add_child(dome)

	# On the wings. These ride on the wing halves, so they tilt with them. The top of a panel
	# is half its thickness up, a little less away from the middle of its chord.
	var skin: float = THICK * 0.5 * 0.92
	var left: Node3D = _wings[0]
	var right: Node3D = _wings[1]
	housing.call(left, -0.95, skin, -0.3, Vector3(0.26, 0.05, 0.18), null)
	housing.call(left, -1.7, skin, -0.26, Vector3(0.12, 0.04, 0.12), red)
	housing.call(right, 1.35, skin, -0.32, Vector3(0.18, 0.045, 0.24), green)
	# Conduit from the left wing's box in to the body, lying on the panel.
	left.add_child(MeshKit.rod(Vector3(-0.82, skin, -0.3), Vector3(-0.3, skin, -0.3), 0.012, dark))


func _build_girl() -> void:
	girl = Girl.new()
	add_child(girl)


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
	# In a real climb (or with the stick hauled right back) she crouches, and not before: an
	# easy pull leaves her standing. As soon as the glider starts to drop away, or the stick is
	# pushed over, her feet come off the deck and she hangs on.
	var climb: float = glider.climb
	var want_crouch: float = maxf(smoothstep(8.0, 17.0, climb), smoothstep(0.8, 1.0, glider.control.y) * 0.85)
	var want_dangle: float = maxf(smoothstep(-3.5, -9.0, climb), smoothstep(-0.3, -0.75, glider.control.y)) * (1.0 - want_crouch)
	var settle: float = 1.0 - exp(-4.5 * delta)
	_crouch = lerpf(_crouch, want_crouch, settle)
	_dangle = lerpf(_dangle, want_dangle, settle)
	var stand: float = clampf(1.0 - _crouch - _dangle, 0.0, 1.0)

	# The three poses, as where her hips are and how far forward she is bent (radians):
	#   standing  knees a little bent, bent well forward over her hands on the low hoops
	#   crouched  hips down close to her heels, more upright
	#   hanging   hips up and back off the deck, body stretched out flat behind her arms
	var hips: Vector3 = Vector3(0, 0.76, 0.03) * stand + Vector3(0, 0.5, 0.18) * _crouch + Vector3(0, 0.74, 0.3) * _dangle
	var lean: float = 1.3 * stand + 0.95 * _crouch + 1.45 * _dangle
	# She leans into a turn a little.
	var bank: float = atan2(-glider.basis.x.y, glider.basis.y.y)
	var roll: float = clampf(bank * 0.12, -0.2, 0.2)

	var hands: Array = []
	var feet: Array = []
	# Her left is the glider's -X, and pose() wants [left, right].
	for side: float in [-1.0, 1.0]:
		# Her fists close round the top bar of each hoop.
		hands.append(Vector3(GRIP.x * side, GRIP.y, GRIP.z))
		# On the deck when standing or crouched; trailing out behind, swinging, when she hangs.
		var planted := Vector3(0.11 * side, DECK + 0.08, 0.02 + _crouch * 0.1)
		var swing: float = sin(_time * 5.0 + side * 1.3)
		var trailing := Vector3(0.13 * side + swing * 0.04, 0.3 + swing * 0.09, 0.98)
		feet.append(planted.lerp(trailing, _dangle))
	girl.pose(hips, lean, roll, hands, feet, _dangle)
