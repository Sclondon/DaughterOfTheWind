extends MeshInstance3D
## A piece of cloth pinned along one edge and left to the wind: the girl's scarf and her skirt,
## the witch's long hair. It is a few strands of linked points side by side. Each point is
## carried along, dragged back by the air, pulled down a little by its weight and shaken by the
## wind, and then the links are pulled back to their proper lengths (strand by strand, and
## across from strand to strand so it stays a sheet). So a scarf trails straight back in fast
## level flight, swings wide in a turn, whips in a roll and hangs when she is slow.
##
## Left alone it is a ribbon: pinned in a row at `root`, `width` across, running off behind.
## Give it a `shape` (a pin and a direction for each strand) and it is any sheet you like, and
## with `closed` the last strand joins back to the first, which makes a skirt. `stiff` pulls it
## back toward the shape it was given, so a skirt stays a skirt in a gale and only flaps, and
## `solids` are things it must stay outside of (her legs).
##
## It lives in world space and is redrawn every frame, two-sided, with smoothed normals so the
## two-tone light falls across it in one clean line and does not pick out the triangles.

const Toon := preload("res://scripts/toon.gd")

const PASSES := 5

## How many strands side by side, and how many links in each.
var strands := 4
var links := 12
## How strongly the air drags on it, how much it weighs, and how hard the wind shakes it.
var drag := 3.2
var weight := 3.5
var flutter := 0.55
## How hard each point is pulled back to its place in the shape it was laid out in (0 not at all).
var stiff := 0.0

## The node it is pinned to (the head, the hips), and where on it (in that node's own space).
var anchor: Node3D
var root := Vector3.ZERO
## Length of one link, and the width of the ribbon where it is pinned and at its end.
var link := 0.16
var width := 0.2
var end_width := 0.34
var color := Color(0.55, 0.27, 0.14)
## The last `hem` links are painted `hem_color` (a trim along the free edge).
var hem := 0
var hem_color := Color.WHITE
## The air's own velocity. Zero in flight (the rider moves through still air); the diorama sets
## it to blow past a rider who is standing still.
var wind := Vector3.ZERO
## For a ribbon: which way is "across" at the pinned end, in the anchor's own space.
var across := Vector3.RIGHT
## For any other sheet: one [pin, direction] per strand, in the anchor's own space. The strand
## is pinned at `pin` and laid out along `direction`.
var shape: Array = []
## True joins the last strand to the first (a tube: a skirt).
var closed := false
## Returns the things the cloth must stay out of, as [end, end, radius] capsules in world space.
var solids := Callable()

var _rest: Array = []  # per strand: where its points belong, in the anchor's space
var _out: Array = []  # per strand: which way is "outward" there, in the anchor's space
var _now: Array = []  # per strand: PackedVector3Array of points, in world space
var _before: Array = []
var _mesh := ImmediateMesh.new()
var _time := 0.0
var _last_pin: Transform3D


func _ready() -> void:
	add_to_group("hair")
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	global_transform = Transform3D.IDENTITY
	mesh = _mesh
	material_override = Toon.tinted()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3.ONE * -100000.0, Vector3.ONE * 200000.0)


## Work out where every point belongs, in the anchor's space.
func _plan() -> void:
	_rest.clear()
	_out.clear()
	if shape.is_empty():
		strands = maxi(strands, 2)
		for s in strands:
			var side: float = float(s) / float(strands - 1) - 0.5
			var strand := PackedVector3Array()
			for i in links + 1:
				strand.append(root + across * side * lerpf(width, end_width, float(i) / float(links)) + Vector3.BACK * link * float(i))
			_rest.append(strand)
			_out.append(Vector3.ZERO)
		return
	strands = shape.size()
	var middle := Vector3.ZERO
	for entry: Array in shape:
		middle += entry[0] as Vector3
	middle /= float(strands)
	for entry: Array in shape:
		var strand := PackedVector3Array()
		for i in links + 1:
			strand.append((entry[0] as Vector3) + (entry[1] as Vector3).normalized() * link * float(i))
		_rest.append(strand)
		_out.append(((entry[0] as Vector3) - middle).normalized())


func _lay_out(t: Transform3D) -> void:
	_now.clear()
	_before.clear()
	for s in strands:
		var strand := PackedVector3Array()
		for i in links + 1:
			strand.append(t * (_rest[s] as PackedVector3Array)[i])
		_now.append(strand)
		_before.append(strand.duplicate())


func _process(delta: float) -> void:
	if anchor == null:
		return
	if _rest.is_empty():
		_plan()
	var t: Transform3D = anchor.get_global_transform_interpolated()
	# Start (or start again after a jump, such as a restart) laid out in its shape.
	if _now.is_empty() or (_now[0] as PackedVector3Array)[0].distance_to(t * (_rest[0] as PackedVector3Array)[0]) > 15.0:
		_lay_out(t)
		_last_pin = t
	# Take the frame in small steps, moving the pinned edge a little each time, so a slow frame
	# cannot leave the cloth behind.
	var steps: int = clampi(ceili(delta * 60.0), 1, 5)
	for step in steps:
		_step(_last_pin.interpolate_with(t, float(step + 1) / float(steps)), delta / float(steps))
	_last_pin = t
	_draw()


func _step(t: Transform3D, dt: float) -> void:
	dt = clampf(dt, 0.001, 1.0 / 30.0)
	_time += dt
	var sheet: bool = not shape.is_empty()

	for s in strands:
		var strand: PackedVector3Array = _now[s]
		var last: PackedVector3Array = _before[s]
		var home: PackedVector3Array = _rest[s]
		var outward: Vector3 = t.basis * (_out[s] as Vector3)
		strand[0] = t * home[0]
		last[0] = strand[0]
		for i in range(1, links + 1):
			var velocity: Vector3 = (strand[i] - last[i]) / dt
			# The air drags against however fast the cloth is moving through it.
			var through: Vector3 = velocity - wind
			var push: Vector3 = Vector3.DOWN * weight - through * drag
			# The wind shakes it: waves that run down the cloth, bigger toward the end and with speed.
			var shake: float = minf(through.length(), 60.0) * flutter * float(i) / float(links)
			if sheet:
				push += outward * sin(_time * 13.0 - i * 0.9 + s * 1.7) * shake
			else:
				push += t.basis.x * sin(_time * 15.0 - i * 0.6 + s * 0.4) * shake
				push += t.basis.y * sin(_time * 11.0 - i * 0.8 + s * 0.7) * shake * 0.7
			if stiff > 0.0:
				push += (t * home[i] - strand[i]) * stiff
			last[i] = strand[i]
			strand[i] += velocity * dt + push * dt * dt
		_now[s] = strand
		_before[s] = last

	var holds: Array = solids.call() if solids.is_valid() else []
	var pairs: int = strands if closed else strands - 1
	# Pull the links back to length.
	for pass_no in PASSES:
		for s in strands:
			var strand: PackedVector3Array = _now[s]
			for i in range(1, links + 1):
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
		for s in pairs:
			var next: int = (s + 1) % strands
			var a: PackedVector3Array = _now[s]
			var b: PackedVector3Array = _now[next]
			var home_a: PackedVector3Array = _rest[s]
			var home_b: PackedVector3Array = _rest[next]
			for i in range(1, links + 1):
				var apart: float = home_a[i].distance_to(home_b[i])
				var gap: Vector3 = b[i] - a[i]
				var long: float = gap.length()
				if long > 0.0001:
					var fix: Vector3 = gap * (1.0 - apart / long) * 0.25
					a[i] += fix
					b[i] -= fix
			_now[s] = a
			_now[next] = b
		if not holds.is_empty():
			_keep_out(holds)
	# Last, walk each strand out from the pinned edge and set every link to exactly its length,
	# so the cloth can swing and fold but never stretch.
	for s in strands:
		var strand: PackedVector3Array = _now[s]
		for i in range(1, links + 1):
			var gap: Vector3 = strand[i] - strand[i - 1]
			if gap.length() > 0.0001:
				strand[i] = strand[i - 1] + gap.normalized() * link
		_now[s] = strand
	if not holds.is_empty():
		_keep_out(holds)


## Push every free point out of the solid things.
func _keep_out(holds: Array) -> void:
	for s in strands:
		var strand: PackedVector3Array = _now[s]
		for i in range(1, links + 1):
			for hold: Array in holds:
				var a: Vector3 = hold[0]
				var b: Vector3 = hold[1]
				var radius: float = hold[2]
				var run: Vector3 = b - a
				var share: float = clampf((strand[i] - a).dot(run) / maxf(run.length_squared(), 0.000001), 0.0, 1.0)
				var off: Vector3 = strand[i] - (a + run * share)
				var far: float = off.length()
				if far < radius and far > 0.0001:
					strand[i] += off * (radius / far - 1.0)
		_now[s] = strand


func _draw() -> void:
	# A normal at every point, from its neighbours on all sides, so the sheet is lit as one
	# smooth surface.
	var normals: Array = []
	for s in strands:
		var before: int = (s - 1 + strands) % strands if closed else maxi(s - 1, 0)
		var after: int = (s + 1) % strands if closed else mini(s + 1, strands - 1)
		var here: PackedVector3Array = _now[s]
		var left: PackedVector3Array = _now[before]
		var right: PackedVector3Array = _now[after]
		var row := PackedVector3Array()
		for i in links + 1:
			var n: Vector3 = (right[i] - left[i]).cross(here[mini(i + 1, links)] - here[maxi(i - 1, 0)])
			row.append(n.normalized() if n.length_squared() > 0.0000000001 else Vector3.UP)
		normals.append(row)

	# Vertex colours are used as they are, so turn the paint into what the shader works in.
	var main: Color = color.srgb_to_linear()
	var trim: Color = hem_color.srgb_to_linear()
	main.a = 0.0
	trim.a = 0.0
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var pairs: int = strands if closed else strands - 1
	for s in pairs:
		var next: int = (s + 1) % strands
		var a: PackedVector3Array = _now[s]
		var b: PackedVector3Array = _now[next]
		var na: PackedVector3Array = normals[s]
		var nb: PackedVector3Array = normals[next]
		for i in links:
			_mesh.surface_set_color(trim if i >= links - hem else main)
			# Both sides of the sheet, each facing its own way.
			for corner: Array in [[a, na, i], [b, nb, i], [a, na, i + 1], [b, nb, i], [b, nb, i + 1], [a, na, i + 1]]:
				_mesh.surface_set_normal(-(corner[1] as PackedVector3Array)[corner[2]])
				_mesh.surface_add_vertex((corner[0] as PackedVector3Array)[corner[2]])
			for corner: Array in [[a, na, i], [a, na, i + 1], [b, nb, i], [b, nb, i], [a, na, i + 1], [b, nb, i + 1]]:
				_mesh.surface_set_normal((corner[1] as PackedVector3Array)[corner[2]])
				_mesh.surface_add_vertex((corner[0] as PackedVector3Array)[corner[2]])
	_mesh.surface_end()
