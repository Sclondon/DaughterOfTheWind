extends MultiMeshInstance3D
## Dust in the air: a thin scatter of pale motes hanging all round the camera. They do not move
## (they are fixed in the world), so as the glider flies they slide past, near ones fast and far
## ones slowly, and that is what tells the eye which way it is going and how quickly, even with
## nothing but sky in view. At speed they draw out into short streaks.
##
## There is only one box of motes. It is repeated end to end in every direction, and the copy
## round the camera is the one that gets drawn, so the dust never runs out.

const COUNT := 320
const BOX := 150.0

## Whoever is flying (for its `velocity`). Without one the motes are just dots.
var flyer: Node3D

var _home: Array = []
var _mm := MultiMesh.new()


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3.ONE * -100000.0, Vector3.ONE * 200000.0)
	var card := QuadMesh.new()
	card.size = Vector2.ONE
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = card
	_mm.instance_count = COUNT
	multimesh = _mm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_fog = true
	material_override = mat
	for i in COUNT:
		_home.append(Vector3(randf(), randf(), randf()) * BOX)


func _process(_delta: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye: Vector3 = cam.global_position
	var facing: Vector3 = cam.global_basis.z
	var speed := Vector3.ZERO
	if flyer:
		speed = flyer.velocity
	# The streak runs along the way the mote slides past, which is against the flight.
	var streak: Vector3 = -speed
	var long: float = clampf(streak.length() * 0.022, 0.09, 2.2)
	var along: Vector3 = streak.normalized() if streak.length() > 1.0 else cam.global_basis.x
	var across: Vector3 = along.cross(facing)
	across = across.normalized() if across.length() > 0.001 else cam.global_basis.y
	var shape := Basis(along * long, across * 0.14, facing)
	var half := Vector3.ONE * BOX * 0.5
	for i in COUNT:
		# The copy of this mote that is nearest the camera.
		var at: Vector3 = eye + ((_home[i] as Vector3) - eye + half).posmod(BOX) - half
		var away: float = at.distance_to(eye)
		# Fade out toward the edge of the box (so none pop) and right in front of the lens.
		var shade: float = (1.0 - smoothstep(BOX * 0.3, BOX * 0.5, away)) * smoothstep(3.0, 12.0, away)
		_mm.set_instance_transform(i, Transform3D(shape, at))
		_mm.set_instance_color(i, Color(1.0, 0.98, 0.9, shade * 0.7))
