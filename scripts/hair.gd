extends MeshInstance3D
## Long hair that streams out behind the rider like a scarf. It is a small piece of cloth: a few
## strands of linked points, pinned to the head at one end. Each point is carried along, dragged
## back by the air, pulled down a little by its weight and shaken by the wind, and then the links
## are pulled back to their proper lengths (strand by strand, and across from strand to strand so
## it stays a ribbon). So it trails straight back in fast level flight, swings wide in a turn,
## whips in a roll and hangs when she is slow.
##
## It lives in world space and is redrawn every frame as a two-sided ribbon.

const Toon := preload("res://scripts/toon.gd")

const STRANDS := 4
const LINKS := 12
## How strongly the air drags on the hair, and how much it weighs.
const DRAG := 3.2
const WEIGHT := 3.5
const PASSES := 5

## The node the hair grows from (the head), and where on it (in that node's own space).
var anchor: Node3D
var root := Vector3.ZERO
## Length of one link, and the width of the hair where it is pinned and at its end.
var link := 0.16
var width := 0.2
var end_width := 0.34
var color := Color(0.55, 0.27, 0.14)

var _now: Array = []  # per strand: PackedVector3Array of points
var _before: Array = []
var _mesh := ImmediateMesh.new()
var _time := 0.0
var _last_pin: Transform3D


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	global_transform = Transform3D.IDENTITY
	mesh = _mesh
	material_override = Toon.paint(color, 5.0, true)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3.ONE * -100000.0, Vector3.ONE * 200000.0)


## Where strand s is pinned, in world space.
func _pin(t: Transform3D, s: int) -> Vector3:
	return t * (root + Vector3((float(s) / float(STRANDS - 1) - 0.5) * width, 0.0, 0.0))


func _lay_out(t: Transform3D) -> void:
	_now.clear()
	_before.clear()
	for s in STRANDS:
		var strand := PackedVector3Array()
		for i in LINKS + 1:
			strand.append(_pin(t, s) + t.basis.z * link * float(i))
		_now.append(strand)
		_before.append(strand.duplicate())


func _process(delta: float) -> void:
	if anchor == null:
		return
	var t: Transform3D = anchor.get_global_transform_interpolated()
	# Start (or start again after a jump, such as a restart) laid straight out behind.
	if _now.is_empty() or (_now[0] as PackedVector3Array)[0].distance_to(_pin(t, 0)) > 15.0:
		_lay_out(t)
		_last_pin = t
	# Take the frame in small steps, moving the pinned end a little each time, so a slow frame
	# cannot leave the hair behind.
	var steps: int = clampi(ceili(delta * 60.0), 1, 5)
	for step in steps:
		_step(_last_pin.interpolate_with(t, float(step + 1) / float(steps)), delta / float(steps))
	_last_pin = t
	_draw_ribbon()


func _step(t: Transform3D, dt: float) -> void:
	dt = clampf(dt, 0.001, 1.0 / 30.0)
	_time += dt

	for s in STRANDS:
		var strand: PackedVector3Array = _now[s]
		var last: PackedVector3Array = _before[s]
		strand[0] = _pin(t, s)
		last[0] = strand[0]
		for i in range(1, LINKS + 1):
			var velocity: Vector3 = (strand[i] - last[i]) / dt
			# Still air drags against however fast the hair is being carried through it.
			var push: Vector3 = Vector3.DOWN * WEIGHT - velocity * DRAG
			# The wind shakes it: waves that run down the hair, bigger toward the end and with speed.
			var shake: float = velocity.length() * 0.55 * float(i) / float(LINKS)
			push += t.basis.x * sin(_time * 15.0 - i * 0.8 + s * 0.5) * shake
			push += t.basis.y * sin(_time * 11.0 - i * 1.1 + s * 0.9) * shake * 0.7
			last[i] = strand[i]
			strand[i] += velocity * dt + push * dt * dt
		_now[s] = strand
		_before[s] = last

	# Pull the links back to length.
	for pass_no in PASSES:
		for s in STRANDS:
			var strand: PackedVector3Array = _now[s]
			for i in range(1, LINKS + 1):
				var gap: Vector3 = strand[i] - strand[i - 1]
				var long: float = gap.length()
				if long > 0.0001:
					# The pinned end does not move; further down, both ends give.
					var fix: Vector3 = gap * (1.0 - link / long)
					if i == 1:
						strand[i] -= fix
					else:
						strand[i] -= fix * 0.5
						strand[i - 1] += fix * 0.5
			_now[s] = strand
		for s in STRANDS - 1:
			var a: PackedVector3Array = _now[s]
			var b: PackedVector3Array = _now[s + 1]
			for i in range(1, LINKS + 1):
				var across: float = lerpf(width, end_width, float(i) / float(LINKS)) / float(STRANDS - 1)
				var gap: Vector3 = b[i] - a[i]
				var long: float = gap.length()
				if long > 0.0001:
					var fix: Vector3 = gap * (1.0 - across / long) * 0.25
					a[i] += fix
					b[i] -= fix
			_now[s] = a
			_now[s + 1] = b
	# Last, walk each strand out from the head and set every link to exactly its length, so the
	# hair can swing and fold but never stretch.
	for s in STRANDS:
		var strand: PackedVector3Array = _now[s]
		for i in range(1, LINKS + 1):
			var gap: Vector3 = strand[i] - strand[i - 1]
			if gap.length() > 0.0001:
				strand[i] = strand[i - 1] + gap.normalized() * link
		_now[s] = strand


func _draw_ribbon() -> void:
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in STRANDS - 1:
		var a: PackedVector3Array = _now[s]
		var b: PackedVector3Array = _now[s + 1]
		for i in LINKS:
			var n: Vector3 = (b[i] - a[i]).cross(a[i + 1] - a[i]).normalized()
			# Both sides of the ribbon, each facing its own way.
			for corner: Vector3 in [a[i], b[i], a[i + 1], b[i], b[i + 1], a[i + 1]]:
				_mesh.surface_set_normal(-n)
				_mesh.surface_add_vertex(corner)
			for corner: Vector3 in [a[i], a[i + 1], b[i], b[i], a[i + 1], b[i + 1]]:
				_mesh.surface_set_normal(n)
				_mesh.surface_add_vertex(corner)
	_mesh.surface_end()
