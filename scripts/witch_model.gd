extends Node3D
## The other rider: a witch on a broomstick. She flies exactly as the glider does (the flight is
## all in glider.gd); only what you see is different. A long broom with a fat bundle of straw
## behind, a witch in a dark robe and a tall bent hat sitting astride it, her cloak streaming
## out behind, a lantern swinging under the handle and a black cat riding on the bristles.
##
## She leans into turns and over the handle in a dive, the cloak and hat tip whip about with the
## speed, the straw flares when she boosts, and the broom leaves one trail of sparks from its
## tail that brightens with speed, hard turns and the boost.

const MeshKit := preload("res://scripts/mesh_kit.gd")
const Trail := preload("res://scripts/trail.gd")
const Toon := preload("res://scripts/toon.gd")
const Hair := preload("res://scripts/hair.gd")

var glider: Node3D

var _witch: Node3D
var _cloak: Node3D
var _hat_tip: Node3D
var _lantern: Node3D
var _straw: Node3D
var _flame: MeshInstance3D
var _trail: MeshInstance3D
var _flame_size := 0.0
var _spark := 0.0
var _time := 0.0


func _ready() -> void:
	var wood := _paint(Color(0.45, 0.3, 0.17), 0.8)
	var straw := _paint(Color(0.72, 0.55, 0.26), 0.9)
	var robe := _paint(Color(0.2, 0.14, 0.3), 0.85)
	var lining := _paint(Color(0.5, 0.16, 0.42), 0.8)
	var skin := _paint(Color(0.95, 0.78, 0.66), 0.8)
	var hair := _paint(Color(0.85, 0.38, 0.12), 0.7)
	var black := _paint(Color(0.07, 0.07, 0.09), 0.7)
	var stripe := _paint(Color(0.92, 0.9, 0.85), 0.8)

	# The broom: handle, a binding, and the straw (a cone, narrow where it is bound).
	add_child(MeshKit.rod(Vector3(0, 0, -1.7), Vector3(0, 0.02, 1.1), 0.04, wood))
	add_child(MeshKit.rod(Vector3(0, 0.02, 1.05), Vector3(0, 0.02, 1.2), 0.11, lining))
	_straw = Node3D.new()
	_straw.position = Vector3(0, 0.02, 1.15)
	add_child(_straw)
	var bundle := CylinderMesh.new()
	bundle.top_radius = 0.09
	bundle.bottom_radius = 0.26
	bundle.height = 1.15
	bundle.radial_segments = 10
	var bristles := MeshInstance3D.new()
	bristles.mesh = bundle
	bristles.material_override = straw
	# The cylinder stands along Y; lay it back along +Z with its wide end trailing.
	bristles.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, 0.575))
	_straw.add_child(bristles)

	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.albedo_color = Color(0.85, 0.5, 1.0, 0.9)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.3
	cone.height = 1.0
	cone.radial_segments = 10
	_flame = MeshInstance3D.new()
	_flame.mesh = cone
	_flame.material_override = glow
	_flame.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.02, 2.4))
	_flame.visible = false
	add_child(_flame)

	# A lantern swinging from the front of the handle.
	_lantern = Node3D.new()
	_lantern.position = Vector3(0, -0.03, -1.55)
	add_child(_lantern)
	_lantern.add_child(MeshKit.rod(Vector3.ZERO, Vector3(0, -0.3, 0), 0.012, black))
	var lamp := MeshInstance3D.new()
	var bulb := SphereMesh.new()
	bulb.radius = 0.1
	bulb.height = 0.22
	bulb.radial_segments = 10
	bulb.rings = 6
	lamp.mesh = bulb
	lamp.material_override = Toon.glowing(Color(1.0, 0.7, 0.3), Color(2.0, 1.3, 0.5))
	lamp.position = Vector3(0, -0.4, 0)
	_lantern.add_child(lamp)

	# The witch, sitting astride and leaning forward over the handle.
	_witch = Node3D.new()
	_witch.position = Vector3(0, 0.05, 0.05)
	add_child(_witch)
	var body := Node3D.new()
	body.rotation.x = -0.45
	_witch.add_child(body)
	var skirt := CylinderMesh.new()
	skirt.top_radius = 0.15
	skirt.bottom_radius = 0.36
	skirt.height = 0.8
	skirt.radial_segments = 12
	var dress := MeshInstance3D.new()
	dress.mesh = skirt
	dress.material_override = robe
	dress.position = Vector3(0, 0.36, 0)
	body.add_child(dress)
	var ball := SphereMesh.new()
	ball.radius = 0.14
	ball.height = 0.28
	ball.radial_segments = 14
	ball.rings = 8
	var head := MeshInstance3D.new()
	head.mesh = ball
	head.material_override = skin
	head.position = Vector3(0, 0.92, -0.02)
	body.add_child(head)
	var locks := MeshInstance3D.new()
	locks.mesh = ball
	locks.material_override = hair
	locks.scale = Vector3(1.1, 1.08, 1.08)
	locks.position = Vector3(0, 0.9, 0.04)
	body.add_child(locks)
	# Her long hair streams out from under the hat.
	var tresses: MeshInstance3D = Hair.new()
	tresses.anchor = head
	tresses.root = Vector3(0, -0.02, 0.13)
	tresses.color = Color(0.85, 0.38, 0.12)
	tresses.width = 0.24
	add_child(tresses)
	# The hat: a wide brim, a cone, and a tip that flops over and whips in the wind.
	var hat := Node3D.new()
	hat.position = Vector3(0, 1.03, 0.0)
	hat.rotation.x = 0.25
	body.add_child(hat)
	var brim_mesh := CylinderMesh.new()
	brim_mesh.top_radius = 0.36
	brim_mesh.bottom_radius = 0.38
	brim_mesh.height = 0.03
	brim_mesh.radial_segments = 16
	var brim := MeshInstance3D.new()
	brim.mesh = brim_mesh
	brim.material_override = black
	hat.add_child(brim)
	var crown_mesh := CylinderMesh.new()
	crown_mesh.top_radius = 0.07
	crown_mesh.bottom_radius = 0.19
	crown_mesh.height = 0.4
	crown_mesh.radial_segments = 12
	var crown := MeshInstance3D.new()
	crown.mesh = crown_mesh
	crown.material_override = black
	crown.position.y = 0.2
	hat.add_child(crown)
	hat.add_child(MeshKit.rod(Vector3(0, 0.05, 0), Vector3(0, 0.05, 0.001), 0.2, lining))
	_hat_tip = Node3D.new()
	_hat_tip.position = Vector3(0, 0.4, 0)
	hat.add_child(_hat_tip)
	var tip_mesh := CylinderMesh.new()
	tip_mesh.top_radius = 0.0
	tip_mesh.bottom_radius = 0.07
	tip_mesh.height = 0.34
	tip_mesh.radial_segments = 10
	var tip := MeshInstance3D.new()
	tip.mesh = tip_mesh
	tip.material_override = black
	tip.position.y = 0.17
	_hat_tip.add_child(tip)

	for side: float in [-1.0, 1.0]:
		# Arms down to the handle, legs hanging either side in striped stockings and boots.
		_witch.add_child(MeshKit.rod(Vector3(0.17 * side, 0.6, -0.3), Vector3(0.05 * side, 0.03, -0.75), 0.045, robe))
		_witch.add_child(MeshKit.rod(Vector3(0.14 * side, 0.1, 0.1), Vector3(0.2 * side, -0.25, -0.12), 0.06, stripe))
		_witch.add_child(MeshKit.rod(Vector3(0.2 * side, -0.25, -0.12), Vector3(0.21 * side, -0.52, 0.0), 0.055, lining))
		_witch.add_child(MeshKit.rod(Vector3(0.21 * side, -0.55, 0.0), Vector3(0.21 * side, -0.57, -0.2), 0.06, black))

	# The cloak: hinged at her shoulders, streaming back over the straw.
	_cloak = Node3D.new()
	_cloak.position = Vector3(0, 0.66, 0.02)
	_witch.add_child(_cloak)
	var cloth := MeshInstance3D.new()
	cloth.mesh = MeshKit.slab(PackedFloat32Array([-0.5, -0.38, -0.2, 0.0, 0.2, 0.38, 0.5]),
			func(x: float) -> Vector2: return Vector2(0.0, 1.5 - absf(x) * 1.1 - x * x * 0.8), 0.05, 5)
	cloth.material_override = robe
	_cloak.add_child(cloth)

	# The cat, riding on the straw.
	var cat := Node3D.new()
	cat.position = Vector3(0, 0.3, 1.55)
	add_child(cat)
	cat.add_child(MeshKit.rod(Vector3(0, 0, -0.12), Vector3(0, 0.02, 0.12), 0.1, black))
	var cat_head := MeshInstance3D.new()
	cat_head.mesh = ball
	cat_head.material_override = black
	cat_head.scale = Vector3.ONE * 0.62
	cat_head.position = Vector3(0, 0.12, -0.2)
	cat.add_child(cat_head)
	for side: float in [-1.0, 1.0]:
		cat.add_child(MeshKit.rod(Vector3(0.05 * side, 0.17, -0.2), Vector3(0.065 * side, 0.25, -0.2), 0.02, black))
	cat.add_child(MeshKit.rod(Vector3(0, 0.05, 0.2), Vector3(0.05, 0.3, 0.3), 0.022, black))

	_trail = Trail.new()
	_trail.source = _straw
	_trail.offset = Vector3(0, 0, 1.2)
	_trail.tint = Color(1.0, 0.86, 0.5)
	_trail.width = 0.2
	add_child(_trail)


func _paint(color: Color, _roughness: float) -> ShaderMaterial:
	return Toon.paint(color, 4.0)


func _process(delta: float) -> void:
	if glider == null:
		return
	_time += delta
	var blend: float = 1.0 - exp(-8.0 * delta)
	var stick: Vector2 = glider.control
	var speed: float = glider.airspeed
	var rush: float = clampf(speed / 60.0, 0.2, 1.4)

	# She leans into the turn, and down over the handle in a dive.
	_witch.rotation.z = lerpf(_witch.rotation.z, -stick.x * 0.3, blend)
	_witch.rotation.x = lerpf(_witch.rotation.x, clampf(-stick.y * 0.18, -0.2, 0.2), blend)

	# The cloak lifts with speed and flaps; the hat tip and the lantern trail behind the motion.
	var flap: float = sin(_time * 11.0 * rush) * 0.09 * rush + sin(_time * 4.3) * 0.05
	_cloak.rotation.x = lerpf(_cloak.rotation.x, lerpf(1.1, 0.32, clampf(speed / 45.0, 0.0, 1.0)) + flap, blend)
	_cloak.rotation.z = lerpf(_cloak.rotation.z, stick.x * 0.35, blend * 0.5)
	_hat_tip.rotation.x = lerpf(_hat_tip.rotation.x, 0.5 + rush * 0.7 + sin(_time * 13.0) * 0.12 * rush, blend)
	_hat_tip.rotation.z = lerpf(_hat_tip.rotation.z, stick.x * 0.6, blend * 0.5)
	_lantern.rotation.x = lerpf(_lantern.rotation.x, -0.25 * rush - stick.y * 0.4 + sin(_time * 3.1) * 0.08, blend * 0.4)
	_lantern.rotation.z = lerpf(_lantern.rotation.z, stick.x * 0.7, blend * 0.4)

	# The straw flares and the tail burns violet when she boosts.
	_flame_size = lerpf(_flame_size, 1.0 if glider.boosting else 0.0, 1.0 - exp(-12.0 * delta))
	_straw.scale = Vector3(1.0 + _flame_size * 0.35, 1.0 + _flame_size * 0.35, 1.0)
	_flame.visible = _flame_size > 0.02
	if _flame.visible:
		var flick: float = 0.85 + 0.15 * sin(_time * 50.0)
		_flame.scale = Vector3(1.0, 2.6 * _flame_size * flick, 1.0)
		_flame.position.z = 2.3 + 1.3 * _flame_size * flick

	# Sparks: always a few, more with speed, with a hard pull or turn, and with the boost.
	var want: float = 0.22 + smoothstep(32.0, 70.0, speed) * 0.45 + clampf((glider.load_factor - 1.15) * 0.5, 0.0, 0.4)
	if glider.boosting:
		want += 0.3
	_spark = lerpf(_spark, clampf(want, 0.0, 1.0), 1.0 - exp(-6.0 * delta))
	_trail.strength = _spark
