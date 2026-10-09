extends Node3D
## The girl's hair: a shaggy mop made of a few dozen chunky locks, the way stylised game hair is
## usually built (solid tapered clumps laid over one another in layers, not a cap and not
## thousands of strands). Each lock is a flattened tube, fat near its root and drawn out to a
## point, laid along the skull from a whorl on the crown and lifting off it toward the tip, so
## the ends stick out every which way. Every lock is a slightly different length, lift, twist
## and shade of the hair colour; that is what makes it read as a mess of separate tufts under
## flat two-tone light.
##
## The upper layers are stiff and are built once, riding on her head. The lower and looser
## locks (round the sides and the back of her neck, and a few strays on top) are each a short
## chain of points on springs: the wind bends them back and shakes them, and they spring home.
##
## Everything is worked out in the skeleton's space (up +Y, her front +Z) around the skull, and
## `frame` takes that into the space of the node the hair rides on.

const Toon := preload("res://scripts/toon.gd")

## Points along a lock's spine, and how it is drawn: rings along it and corners round it.
const SPINE := 6
const RINGS := 8
const AROUND := 6
## How far back from straight up the whorl on her crown is (radians).
const TILT := 0.42
## How far round from the whorl a lock can follow the skull before it hangs free.
const LEAVE := 2.0

## The node the hair rides on (her head), and the skeleton's space seen from that node.
var anchor: Node3D
var frame := Transform3D.IDENTITY
## Her skull: its middle and its half-width, half-height and half-depth, in the skeleton's space.
var centre := Vector3(0, 1.392, -0.002)
var radii := Vector3(0.102, 0.13, 0.106)
var color := Color(0.58, 0.27, 0.13)
## The air's own velocity (see hair.gd).
var wind := Vector3.ZERO

var _loose: Array = []  # the locks that move: {home, normals, width, tint, give, now, before}
var _fixed_mesh := MeshInstance3D.new()
var _loose_mesh := MeshInstance3D.new()
var _drawn := ArrayMesh.new()
var _indices := PackedInt32Array()
var _time := 0.0
var _last_pin: Transform3D


func _ready() -> void:
	add_to_group("hair")
	var material: ShaderMaterial = Toon.tinted()
	material.set_shader_parameter("albedo", color)
	material.set_shader_parameter("rim", 0.3)

	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var still: Array = []
	# Layer by layer, from the crown down. Each: how many, where round the head (middle and
	# half-spread of the arc, 0 is her front), how far from the whorl it starts, how much
	# further than the hairline it runs, lift at the tip, width, and how freely it moves.
	var layers := [
		[16, 0.0, PI, 0.0, 0.22, 0.0, 0.03, 0.105, 0.0],  # the top, over everything
		[13, PI, 2.35, 0.6, 1.0, 0.12, 0.04, 0.1, 0.45],  # sides and back, to the jaw
		[9, PI, 1.5, 1.25, 1.55, 0.42, 0.05, 0.092, 1.0],  # the back of her neck, longest
		[5, 0.0, PI, 0.1, 0.5, -0.75, 0.09, 0.05, 0.7],  # strays sticking up
	]
	for layer: Array in layers:
		var count: int = layer[0]
		for k in count:
			var turn: float = (layer[1] as float) + (layer[2] as float) * ((float(k) + rng.randf_range(0.15, 0.85)) / float(count) * 2.0 - 1.0)
			var lock: Dictionary = _grow(rng, turn, rng.randf_range(layer[3], layer[4]), layer[5], layer[6], layer[7])
			lock["give"] = layer[8]
			if (layer[8] as float) > 0.2:
				_loose.append(lock)
			else:
				still.append(lock)

	# The stiff locks: one mesh, built once, riding on her head.
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var tints := PackedColorArray()
	for lock: Dictionary in still:
		_skin(lock["home"], lock["normals"], lock["width"], lock["tint"], verts, norms, tints)
	_fixed_mesh.mesh = _as_mesh(verts, norms, tints, _index(still.size()))
	_fixed_mesh.material_override = material
	if anchor:
		anchor.add_child(_fixed_mesh)
	else:
		add_child(_fixed_mesh)

	# The loose ones live in world space and are redrawn every frame.
	_indices = _index(_loose.size())
	_loose_mesh.top_level = true
	_loose_mesh.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_loose_mesh.mesh = _drawn
	_loose_mesh.material_override = material
	_loose_mesh.custom_aabb = AABB(Vector3.ONE * -100000.0, Vector3.ONE * 200000.0)
	add_child(_loose_mesh)
	_loose_mesh.global_transform = Transform3D.IDENTITY


## A place on (or, past LEAVE, hanging below) the skull: `from_whorl` is the angle from the
## whorl on her crown, `turn` the way round her head from her front.
func _on_skull(from_whorl: float, turn: float) -> Vector3:
	var crown := Vector3(0, cos(TILT), -sin(TILT))
	var ahead: Vector3 = (Vector3.BACK - crown * crown.dot(Vector3.BACK)).normalized()
	var aside: Vector3 = crown.cross(ahead)
	var round_it: Vector3 = ahead * cos(turn) + aside * sin(turn)
	var held: float = minf(from_whorl, LEAVE)
	var at: Vector3 = centre + (crown * cos(held) + round_it * sin(held)) * radii
	if from_whorl > LEAVE:
		# Off the skull: carry straight on the way it was going, sagging a little.
		var going: Vector3 = ((-crown * sin(held) + round_it * cos(held)) * radii).normalized()
		at += (going * 0.8 + Vector3.DOWN * 0.45) * (from_whorl - LEAVE) * 0.11
	return at


## One lock: its spine and the way "out from the head" is at each point, in the anchor's space.
func _grow(rng: RandomNumberGenerator, turn: float, start: float, extra: float, lift: float, width: float) -> Dictionary:
	# Where the hairline is, going round: above the goggles in front, the jaw at the sides,
	# the nape behind.
	var facing: float = cos(turn)
	var hairline: float = 2.12 + (1.55 - 2.12) * maxf(facing, 0.0) + (2.3 - 2.12) * maxf(-facing, 0.0)
	var finish: float = maxf(hairline * rng.randf_range(0.9, 1.06) + extra, start + 0.5)
	var twist: float = rng.randf_range(-0.42, 0.42)
	var tip_lift: float = lift * rng.randf_range(0.5, 1.7)
	var home := PackedVector3Array()
	var normals := PackedVector3Array()
	for i in SPINE:
		var t: float = float(i) / float(SPINE - 1)
		var at: Vector3 = _on_skull(lerpf(start, finish, t), turn + twist * t * t)
		var out: Vector3 = ((at - centre) / radii).normalized()
		# Lying a little proud of the skull, and lifting off it toward the tip.
		at += out * (0.006 + tip_lift * t * t)
		home.append(frame * at)
		normals.append((frame.basis * out).normalized())
	return {
		"home": home, "normals": normals,
		"width": width * rng.randf_range(0.8, 1.15),
		"tint": rng.randf_range(0.74, 1.16),
	}


func _process(delta: float) -> void:
	if anchor == null or _loose.is_empty():
		return
	var t: Transform3D = anchor.get_global_transform_interpolated()
	var first: Dictionary = _loose[0]
	if not first.has("now") or ((first["now"] as PackedVector3Array)[0]).distance_to(t * (first["home"] as PackedVector3Array)[0]) > 15.0:
		for lock: Dictionary in _loose:
			var laid := PackedVector3Array()
			for at: Vector3 in (lock["home"] as PackedVector3Array):
				laid.append(t * at)
			lock["now"] = laid
			lock["before"] = laid.duplicate()
		_last_pin = t
	var steps: int = clampi(ceili(delta * 60.0), 1, 5)
	for step in steps:
		_step(_last_pin.interpolate_with(t, float(step + 1) / float(steps)), delta / float(steps))
	_last_pin = t

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var tints := PackedColorArray()
	for lock: Dictionary in _loose:
		var out := PackedVector3Array()
		for n: Vector3 in (lock["normals"] as PackedVector3Array):
			out.append(t.basis * n)
		_skin(lock["now"], out, lock["width"], lock["tint"], verts, norms, tints)
	_drawn.clear_surfaces()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = tints
	arrays[Mesh.ARRAY_INDEX] = _indices
	_drawn.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _step(t: Transform3D, dt: float) -> void:
	dt = clampf(dt, 0.001, 1.0 / 30.0)
	_time += dt
	for n in _loose.size():
		var lock: Dictionary = _loose[n]
		var home: PackedVector3Array = lock["home"]
		var now: PackedVector3Array = lock["now"]
		var before: PackedVector3Array = lock["before"]
		var give: float = lock["give"]
		# The root and the first point ride on her head.
		for i in 2:
			now[i] = t * home[i]
			before[i] = now[i]
		for i in range(2, SPINE):
			var along: float = float(i - 1) / float(SPINE - 2)
			var velocity: Vector3 = (now[i] - before[i]) / dt
			var through: Vector3 = velocity - wind
			var push: Vector3 = Vector3.DOWN * 2.0 - through * (0.5 + 2.2 * give) * along
			var shake: float = minf(through.length(), 60.0) * 0.5 * give * along
			push += t.basis.x * sin(_time * 17.0 + n * 2.1 - i * 0.7) * shake
			push += t.basis.y * sin(_time * 13.0 + n * 1.3 - i * 0.9) * shake * 0.8
			# The spring home: firm near the root, soft at the tip, softer the looser the lock.
			push += (t * home[i] - now[i]) * lerpf(900.0, 170.0, give) * (1.0 - 0.55 * along)
			before[i] = now[i]
			now[i] += velocity * dt + push * dt * dt
		# It can bend, but not stretch.
		for i in range(2, SPINE):
			var gap: Vector3 = now[i] - now[i - 1]
			if gap.length() > 0.0001:
				now[i] = now[i - 1] + gap.normalized() * home[i].distance_to(home[i - 1])
		lock["now"] = now
		lock["before"] = before


## Draw one lock into the arrays: a flattened tube round its spine, fat near the root and
## drawn out to a point.
func _skin(spine: PackedVector3Array, out: PackedVector3Array, width: float, tint: float,
		verts: PackedVector3Array, norms: PackedVector3Array, tints: PackedColorArray) -> void:
	var shade := Color(tint, tint, tint, 0.0)
	var last: int = SPINE - 1
	for r in RINGS:
		var t: float = float(r) / float(RINGS - 1)
		var along: float = t * float(last)
		var i: int = mini(int(along), last - 1)
		var part: float = along - float(i)
		# A smooth curve through the spine's points.
		var a: Vector3 = spine[maxi(i - 1, 0)]
		var b: Vector3 = spine[i]
		var c: Vector3 = spine[i + 1]
		var d: Vector3 = spine[mini(i + 2, last)]
		var at: Vector3 = 0.5 * ((2.0 * b) + (c - a) * part + (2.0 * a - 5.0 * b + 4.0 * c - d) * part * part + (3.0 * b - a - 3.0 * c + d) * part * part * part)
		var going: Vector3 = (0.5 * ((c - a) + (2.0 * a - 5.0 * b + 4.0 * c - d) * 2.0 * part + (3.0 * b - a - 3.0 * c + d) * 3.0 * part * part)).normalized()
		var up: Vector3 = out[i].lerp(out[i + 1], part)
		var side: Vector3 = going.cross(up)
		side = side.normalized() if side.length_squared() > 0.000001 else Vector3.RIGHT
		up = side.cross(going)
		# Swelling out from the root, then tapering to a point.
		var size: float = width * (0.7 + 0.3 * sin(minf(t * 3.0, 1.0) * PI * 0.5)) * maxf(1.0 - pow(t, 2.6), 0.03)
		var wide: float = size * 0.5
		var deep: float = size * 0.17
		for k in AROUND:
			var angle: float = TAU * float(k) / float(AROUND)
			verts.append(at + side * cos(angle) * wide + up * sin(angle) * deep)
			norms.append((side * cos(angle) * deep + up * sin(angle) * wide).normalized())
			tints.append(shade)


## The triangles for `count` locks.
func _index(count: int) -> PackedInt32Array:
	var indices := PackedInt32Array()
	for n in count:
		var first: int = n * RINGS * AROUND
		for r in RINGS - 1:
			for k in AROUND:
				var a: int = first + r * AROUND + k
				var b: int = first + r * AROUND + (k + 1) % AROUND
				indices.append_array([a, a + AROUND, b, b, a + AROUND, b + AROUND])
	return indices


func _as_mesh(verts: PackedVector3Array, norms: PackedVector3Array, tints: PackedColorArray, indices: PackedInt32Array) -> ArrayMesh:
	var made := ArrayMesh.new()
	if verts.is_empty():
		return made
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = tints
	arrays[Mesh.ARRAY_INDEX] = indices
	made.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return made
