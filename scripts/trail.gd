extends MeshInstance3D
## A ribbon of vapour left behind a point on the glider (a wingtip). It lives in world space,
## turns to face the camera, and fades along its length. `strength` (0..1) is how much vapour is
## coming off right now; the glider model sets it from how hard that tip is working. Stronger
## vapour is brighter, wider and hangs in the air longer.

const LIFE := 2.4
const SPACING := 0.6
const WIDTH := 0.07

var source: Node3D
var offset := Vector3.ZERO
var strength := 0.0
var tint := Color.WHITE
var width := WIDTH

var _points: Array = []  # each [Vector3 position, float born, float strength]
var _mesh := ImmediateMesh.new()


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	global_transform = Transform3D.IDENTITY
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = mat
	# The ribbon is rebuilt in world space every frame, so never cull it by its old bounds.
	custom_aabb = AABB(Vector3.ONE * -100000.0, Vector3.ONE * 200000.0)


func clear() -> void:
	_points.clear()
	_mesh.clear_surfaces()


## How long vapour of a given strength lasts.
func _life(s: float) -> float:
	return LIFE * (0.25 + 0.75 * s)


func _process(_delta: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if source == null or cam == null:
		return
	var now: float = Time.get_ticks_msec() * 0.001
	var tip: Vector3 = source.get_global_transform_interpolated() * offset
	if _points.is_empty() or (_points[-1][0] as Vector3).distance_to(tip) > SPACING:
		# A jump this big is a teleport (a reset), not flight.
		if not _points.is_empty() and (_points[-1][0] as Vector3).distance_to(tip) > 60.0:
			_points.clear()
		_points.append([tip, now, strength])
	while not _points.is_empty() and now - (_points[0][1] as float) > LIFE:
		_points.pop_front()

	_mesh.clear_surfaces()
	if _points.size() < 2:
		return
	var eye: Vector3 = cam.global_position
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in _points.size() + 1:
		# The last point of the ribbon is the tip itself, so it never lags behind the wing.
		var p: Vector3 = tip
		var age: float = 0.0
		var s: float = strength
		if i < _points.size():
			p = _points[i][0]
			s = _points[i][2]
			age = minf((now - (_points[i][1] as float)) / _life(s), 1.0)
		var before: Vector3 = _points[maxi(i - 1, 0)][0]
		var after: Vector3 = tip if i + 1 >= _points.size() else (_points[i + 1][0] as Vector3)
		var along: Vector3 = after - before
		var side: Vector3 = along.cross(eye - p)
		if side.length() < 0.0001:
			side = Vector3.UP
		side = side.normalized() * width * (0.6 + s) * (1.0 + age * 1.5)
		# Vapour right in front of the lens would fill the screen, so it thins out near the camera.
		var close: float = smoothstep(3.0, 8.0, eye.distance_to(p))
		var color := Color(tint.r, tint.g, tint.b, s * (1.0 - age) * (1.0 - age) * 0.55 * close)
		_mesh.surface_set_color(color)
		_mesh.surface_add_vertex(p + side)
		_mesh.surface_set_color(color)
		_mesh.surface_add_vertex(p - side)
	_mesh.surface_end()
