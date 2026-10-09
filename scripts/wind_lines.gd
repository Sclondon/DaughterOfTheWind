extends MeshInstance3D
## The wind, drawn: white streaks that sweep across the sky the way they do in The Wind Waker.
## Each one runs along the wind for a way, curls over in a loop, and runs on, drawing itself
## from one end and fading from the other. They show which way the air is moving and give the
## eye something to measure speed against.
##
## A handful are alive at once, always somewhere ahead of the camera. All of them are one mesh,
## rebuilt every frame as thin ribbons turned to face the camera.

const COUNT := 9
const STEPS := 30
## How much of a streak is drawn at once, as a share of its whole length.
const SHOWN := 0.42

## Which way the wind blows.
var wind := Vector3(1, 0, 0.2)

var _gusts: Array = []  # each [Vector3 start, Vector3 along, float length, float loop radius, float age, float life]
var _mesh := ImmediateMesh.new()


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	global_transform = Transform3D.IDENTITY
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3.ONE * -100000.0, Vector3.ONE * 200000.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_fog = true
	material_override = mat
	for i in COUNT:
		# Start them at different points in their lives, so they do not all appear together.
		_gusts.append([Vector3.ZERO, Vector3.RIGHT, 100.0, 8.0, randf_range(0.0, 3.0), 0.0])


## Where a streak is at a share t (0..1) of the way along it: straight, a loop, straight again.
func _along(gust: Array, t: float) -> Vector3:
	var start: Vector3 = gust[0]
	var dir: Vector3 = gust[1]
	var long: float = gust[2]
	var radius: float = gust[3]
	if t < 0.4:
		return start + dir * (t / 0.4) * long * 0.5
	if t < 0.68:
		var turn: float = (t - 0.4) / 0.28 * TAU
		return start + dir * (long * 0.5 + sin(turn) * radius) + Vector3.UP * (1.0 - cos(turn)) * radius
	return start + dir * (long * 0.5 + (t - 0.68) / 0.32 * long * 0.5)


func _process(delta: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye: Vector3 = cam.global_position
	var ahead: Vector3 = -cam.global_basis.z
	var blow: Vector3 = wind.normalized() if wind.length() > 0.01 else Vector3.RIGHT
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var drawn := false
	for gust: Array in _gusts:
		gust[4] = (gust[4] as float) + delta
		if (gust[4] as float) > (gust[5] as float):
			# A new one: somewhere out in front, across the view, running with the wind.
			var long: float = randf_range(70.0, 150.0)
			var dir: Vector3 = (blow + Vector3(randf_range(-0.15, 0.15), randf_range(-0.06, 0.06), randf_range(-0.15, 0.15))).normalized()
			var middle: Vector3 = eye + ahead * randf_range(90.0, 320.0) + cam.global_basis.x * randf_range(-170.0, 170.0) \
					+ Vector3.UP * randf_range(-70.0, 80.0)
			gust[0] = middle - dir * long * 0.5
			gust[1] = dir
			gust[2] = long
			gust[3] = randf_range(5.0, 12.0)
			gust[4] = 0.0
			gust[5] = randf_range(2.6, 4.2)
		# The drawn stretch slides from one end of the streak to the other over its life.
		var head: float = (gust[4] as float) / (gust[5] as float) * (1.0 + SHOWN)
		var from: float = clampf(head - SHOWN, 0.0, 1.0)
		var to: float = clampf(head, 0.0, 1.0)
		if to - from < 0.01:
			continue
		var last_left := Vector3.ZERO
		var last_right := Vector3.ZERO
		var last_shade := 0.0
		for i in STEPS + 1:
			var share: float = float(i) / float(STEPS)
			var t: float = lerpf(from, to, share)
			var p: Vector3 = _along(gust, t)
			var heading: Vector3 = _along(gust, minf(t + 0.01, 1.0)) - _along(gust, maxf(t - 0.01, 0.0))
			var side: Vector3 = heading.cross(eye - p)
			side = side.normalized() if side.length() > 0.0001 else Vector3.UP
			# Thin at both ends, and faint there too.
			var taper: float = sin(share * PI)
			var half: float = 0.4 * taper + 0.03
			var shade: float = taper * 0.7 * smoothstep(40.0, 90.0, eye.distance_to(p))
			var left: Vector3 = p + side * half
			var right: Vector3 = p - side * half
			if i > 0:
				for corner: Array in [[last_left, last_shade], [last_right, last_shade], [left, shade],
						[last_right, last_shade], [right, shade], [left, shade]]:
					_mesh.surface_set_color(Color(1, 1, 1, corner[1]))
					_mesh.surface_add_vertex(corner[0])
				drawn = true
			last_left = left
			last_right = right
			last_shade = shade
	if not drawn:
		# An ImmediateMesh surface may not be empty.
		for i in 3:
			_mesh.surface_set_color(Color(1, 1, 1, 0))
			_mesh.surface_add_vertex(eye)
	_mesh.surface_end()
