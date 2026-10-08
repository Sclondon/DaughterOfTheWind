extends Node3D
## What the glider looks like: a white gull wing, a slim body with a jet in the tail, a grab bar,
## and a small pilot in blue lying along the top. All of it is built here from MeshKit shapes.
## It also owns the two wingtip vapour trails and the jet flame.

const MeshKit := preload("res://scripts/mesh_kit.gd")
const Trail := preload("res://scripts/trail.gd")

const HALF_SPAN := 3.1

var glider: Node3D

var _pilot: Node3D
var _flame: MeshInstance3D
var _flame_mat: StandardMaterial3D
var _trails: Array = []
var _flame_size := 0.0


func _ready() -> void:
	var white := _paint(Color(0.97, 0.97, 0.94), 0.45)
	var cream := _paint(Color(0.86, 0.85, 0.8), 0.6)
	var dark := _paint(Color(0.16, 0.17, 0.2), 0.5)

	var wing := MeshInstance3D.new()
	wing.mesh = MeshKit.wing(HALF_SPAN, 1.55, 0.5, 0.75, 0.115, _gull, 28, 9)
	wing.material_override = white
	add_child(wing)

	var body := MeshInstance3D.new()
	body.mesh = MeshKit.body(2.75, _body_shape, 14, 16)
	body.material_override = white
	body.position = Vector3(0, 0.02, 0.1)
	add_child(body)

	# The jet in the tail.
	add_child(MeshKit.rod(Vector3(0, 0.03, 1.3), Vector3(0, 0.03, 1.5), 0.13, dark))
	_flame_mat = StandardMaterial3D.new()
	_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flame_mat.albedo_color = Color(1.0, 0.75, 0.4, 0.9)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.12
	cone.height = 1.0
	cone.radial_segments = 10
	_flame = MeshInstance3D.new()
	_flame.mesh = cone
	_flame.material_override = _flame_mat
	# The cone's point trails behind (+Z); its base sits in the nozzle.
	_flame.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.03, 1.6))
	_flame.visible = false
	add_child(_flame)

	# The grab bar: two posts and a crossbar.
	for side: float in [-1.0, 1.0]:
		add_child(MeshKit.rod(Vector3(0.2 * side, 0.24, -0.42), Vector3(0.21 * side, 0.6, -0.58), 0.022, cream))
	add_child(MeshKit.rod(Vector3(-0.21, 0.6, -0.58), Vector3(0.21, 0.6, -0.58), 0.024, cream))

	_build_pilot()

	for side: float in [-1.0, 1.0]:
		var trail: MeshInstance3D = Trail.new()
		trail.source = self
		trail.offset = Vector3(HALF_SPAN * 0.98 * side, _gull(1.0), 0.45)
		add_child(trail)
		_trails.append(trail)


## The gull curve: the wing lifts out of the body, then droops a little toward the tip.
func _gull(a: float) -> float:
	return 0.78 * pow(a, 0.8) - 0.62 * a * a * a


func _body_shape(t: float) -> Vector3:
	var r: float = 0.34 * pow(sin(PI * pow(t, 0.55) * 0.93), 0.7)
	r = maxf(r, 0.012)
	return Vector3(r, r * 0.78, 0.0)


func _build_pilot() -> void:
	var tunic := _paint(Color(0.2, 0.42, 0.78), 0.8)
	var skin := _paint(Color(0.95, 0.78, 0.66), 0.8)
	var hair := _paint(Color(0.55, 0.27, 0.14), 0.7)
	var cloth := _paint(Color(0.93, 0.9, 0.82), 0.85)
	var boots := _paint(Color(0.45, 0.32, 0.22), 0.8)

	_pilot = Node3D.new()
	add_child(_pilot)
	# She lies along the body, chest up on her arms, legs trailing.
	_pilot.add_child(MeshKit.rod(Vector3(0, 0.5, -0.12), Vector3(0, 0.4, 0.5), 0.15, tunic))
	var head := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.125
	ball.height = 0.25
	ball.radial_segments = 14
	ball.rings = 8
	head.mesh = ball
	head.material_override = skin
	head.position = Vector3(0, 0.66, -0.3)
	_pilot.add_child(head)
	var mop := MeshInstance3D.new()
	mop.mesh = ball
	mop.material_override = hair
	mop.scale = Vector3(1.1, 1.05, 1.1)
	mop.position = Vector3(0, 0.69, -0.25)
	_pilot.add_child(mop)
	for side: float in [-1.0, 1.0]:
		_pilot.add_child(MeshKit.rod(Vector3(0.17 * side, 0.52, -0.1), Vector3(0.2 * side, 0.6, -0.55), 0.045, tunic))
		_pilot.add_child(MeshKit.rod(Vector3(0.09 * side, 0.4, 0.5), Vector3(0.11 * side, 0.37, 1.0), 0.07, cloth))
		_pilot.add_child(MeshKit.rod(Vector3(0.11 * side, 0.37, 1.0), Vector3(0.12 * side, 0.36, 1.32), 0.06, boots))


func _paint(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat


func _process(delta: float) -> void:
	if glider == null:
		return
	# The pilot leans into the turn.
	var bank: float = atan2(-glider.basis.x.y, glider.basis.y.y)
	_pilot.rotation.z = lerpf(_pilot.rotation.z, clampf(-bank * 0.12, -0.2, 0.2), 1.0 - exp(-6.0 * delta))

	_flame_size = lerpf(_flame_size, 1.0 if glider.boosting else 0.0, 1.0 - exp(-12.0 * delta))
	_flame.visible = _flame_size > 0.02
	if _flame.visible:
		var flick: float = 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.05)
		_flame.scale = Vector3(1.0, 2.6 * _flame_size * flick, 1.0)
		_flame.position.z = 1.5 + 1.3 * _flame_size * flick

	# Vapour streams off the tips when the wing is working hard, or going fast.
	var strength: float = (glider.load_factor - 1.15) * 0.7 + (glider.airspeed - 46.0) / 40.0
	if glider.boosting:
		strength += 0.5
	strength = clampf(strength, 0.06, 1.0)
	for trail in _trails:
		trail.strength = strength
