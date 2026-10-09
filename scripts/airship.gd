extends Node3D
## One giant metal airship, built in code: a hull of matte rusty plate with slab wings, propeller
## engines, a twin tail, a bridge slung under the nose and glass bubble turrets set into its back
## and flanks. The skin is plain (shaders/hull); what makes it busy is real fittings bolted on:
## ribs, pipes, housings, stacks and masts, all one mesh (`_add_fittings()`). `build()` takes a
## length and a seed, so every ship in a fleet comes out a different size and cut.
##
## It cruises straight ahead (-Z) with a slow heave. `hit()` tells the glider when it has flown
## into the hull or a wing and which way to push it back out.
##
## Its turrets fire shells through `flak` while `armed`, and what they are fighting is the other
## side's ships (`foes`): every gun hammers the nearest one. Only one gun in three is a flak gun
## that will turn on `target` (the glider), and only when she comes close. They lead what they
## shoot at, so flying straight gets you hit and turning does not. The guns sit along the back
## of the ship and cannot point down at her past the deck: underneath a ship is out of their sight.
##
## A ship has `health`. Enemy shells that reach the hull wear it down (`take_hit()`), which shows
## on the bar floating over it and in the smoke pouring from where it was holed. At nothing it
## goes `down`: it blows up, rolls over and falls out of the sky, and a while later a fresh ship
## comes down out of the heights to take its place in the line.

const MeshKit := preload("res://scripts/mesh_kit.gd")
const HullShader := preload("res://shaders/hull.gdshader")
const BarShader := preload("res://shaders/health_bar.gdshader")
const Toon := preload("res://scripts/toon.gd")

## Each side's colours: [hull paints to pick from, the stripe].
const LIVERY := [
	[[Color(0.42, 0.42, 0.6), Color(0.36, 0.4, 0.58), Color(0.47, 0.45, 0.63)], Color(0.85, 0.68, 0.2)],
	[[Color(0.5, 0.25, 0.18), Color(0.43, 0.3, 0.2), Color(0.38, 0.2, 0.17)], Color(0.9, 0.86, 0.76)],
]
## The hull's cross-section: how square it is, and how much its underside is flattened.
const HULL_POWER := 3.2
const HULL_BELLY := 0.85
const RUST := Color(0.3, 0.17, 0.1)

var length := 240.0
var speed := 13.0
var heading := 0.0
var cruise_y := 560.0
## What the turrets shoot at (the glider; it needs `velocity`), where the shells go, and whether to fire.
var target: Node3D
var flak: Node
var armed := true
## The other side's ships.
var foes: Array = []
## Which side it is on (0 or 1).
var faction := 0
## How much it can take (set from its length in build()) and how much it has left.
var max_health := 70.0
var health := 70.0
## True from the moment it is beaten until a fresh ship has taken its place.
var down := false
## A falling ship is gone when it gets this low (the sea, or the sea of clouds).
var floor_y := 0.0
# For the tests.
var losses := 0
var shots_at_glider := 0

## How near the glider has to come before the flak guns bother with her.
const GUN_RANGE := 600.0
## How long a beaten ship takes to fall, how long its place stays empty, and how far up the
## fresh one starts.
const SINK_TIME := 26.0
const AWAY_TIME := 14.0
const ARRIVE_HEIGHT := 520.0
## How far the guns reach for another ship.
const FOE_RANGE := 1900.0
## How far off a perfect aim a shot can go, as a slope (0.02 is about one degree).
const GUN_SPREAD := 0.02

var _half_w := 20.0
var _half_h := 17.0
var _capsules: Array = []  # wings and tail, in local space: [Vector3 a, Vector3 b, float radius]
var _props: Array = []
var _turrets: Array = []  # each [Node3D gun, float seconds until it may fire again, float barrel length]
var _metal: ShaderMaterial
var _dark: ShaderMaterial
var _glass: ShaderMaterial
var _fit: ShaderMaterial
var _fittings: SurfaceTool  # everything bolted to the hull, gathered into one mesh
var _bubbles: SurfaceTool  # and all the glass
var _time := 0.0
var _phase := 0.0
var _bar: MeshInstance3D
var _bar_paint: ShaderMaterial
var _wounds: Array = []  # where it has been holed (local points); smoke pours from each
var _smoke := 0.0
var _fall := 0.0  # seconds since it was beaten
var _fall_speed := 0.0
var _drop := 0.0  # how far above (+) or below (-) its cruising height it is
var _lean := Vector2.ZERO  # extra pitch and roll while it falls
var _list := 1.0  # which way it rolls over
var _next_blast := 0.0


func build(ship_length: float, ship_seed: int, faction: int = 0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = ship_seed
	length = ship_length
	self.faction = faction
	max_health = length * 0.8
	health = max_health
	_list = 1.0 if rng.randf() < 0.5 else -1.0
	_phase = rng.randf() * TAU
	_half_w = length * rng.randf_range(0.085, 0.105)
	_half_h = length * rng.randf_range(0.074, 0.09)

	# Wings and fittings share the plain plating; the hull gets its own copy with paintwork.
	var paints: Array = LIVERY[faction][0]
	var paint: Color = paints[rng.randi() % paints.size()]
	_metal = ShaderMaterial.new()
	_metal.shader = HullShader
	_metal.set_shader_parameter("base_color", paint)
	var hull_metal := ShaderMaterial.new()
	hull_metal.shader = HullShader
	hull_metal.set_shader_parameter("base_color", paint)
	hull_metal.set_shader_parameter("is_hull", true)
	hull_metal.set_shader_parameter("hull_length", length)
	hull_metal.set_shader_parameter("half_height", _half_h)
	hull_metal.set_shader_parameter("stripe_color", LIVERY[faction][1])
	_dark = Toon.paint(Color(0.14, 0.14, 0.16))
	_glass = Toon.glowing(Color(0.1, 0.1, 0.1), Color(1.6, 1.25, 0.7))
	_fit = Toon.paint(paint.lerp(RUST, 0.3).darkened(0.14))
	_fittings = SurfaceTool.new()
	_fittings.begin(Mesh.PRIMITIVE_TRIANGLES)
	_bubbles = SurfaceTool.new()
	_bubbles.begin(Mesh.PRIMITIVE_TRIANGLES)

	var hull := MeshInstance3D.new()
	hull.mesh = MeshKit.body(length, _hull_shape, 32, 36, HULL_POWER, HULL_BELLY)
	hull.material_override = hull_metal
	add_child(hull)

	# A long hump of upper decks along the back.
	var hump := MeshInstance3D.new()
	var hump_size := Vector3(_half_w * 0.5, _half_h * 0.45, length * 0.34)
	hump.mesh = MeshKit.body(hump_size.z, func(t: float) -> Vector3:
		var r: float = maxf(pow(sin(PI * pow(t, 0.75)), 0.4), 0.05)
		return Vector3(hump_size.x * r, hump_size.y * r, 0.0), 16, 14, 3.0)
	hump.material_override = _metal
	hump.position = Vector3(0, _hull_shape(0.38).z + _half_h * 0.86, -length * 0.12)
	add_child(hump)

	# Main wings, then a smaller pair further back.
	var span: float = length * rng.randf_range(0.3, 0.37)
	_add_wing(Vector3(0, _half_h * 0.1, -length * 0.13), span, length * 0.2, length * 0.1, length * 0.06, 2)
	_add_wing(Vector3(0, _half_h * 0.4, length * 0.17), span * 0.6, length * 0.12, length * 0.065, length * 0.03, 1)

	# Twin tail: a wide stabiliser with a fin standing on each end.
	var tail_z: float = length * 0.41
	var tail_y: float = _hull_shape(0.91).z + _half_h * 0.25
	var tail_span: float = length * 0.17
	_add_wing(Vector3(0, tail_y, tail_z), tail_span, length * 0.09, length * 0.055, length * 0.025, 0)
	for side: float in [-1.0, 1.0]:
		var fin := MeshInstance3D.new()
		fin.mesh = MeshKit.wing(length * 0.08, length * 0.1, length * 0.055, length * 0.025, 0.1, _flat, 6, 5)
		fin.material_override = _metal
		fin.transform = Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(tail_span * 0.92 * side, tail_y, tail_z))
		add_child(fin)

	_add_bridge()
	_add_turrets(rng)
	_add_fittings(rng)
	for pair: Array in [[_fittings, _fit], [_bubbles, Toon.shiny(Color(0.4, 0.58, 0.68))]]:
		var piece := MeshInstance3D.new()
		piece.mesh = (pair[0] as SurfaceTool).commit()
		piece.material_override = pair[1]
		add_child(piece)
	_fittings = null
	_bubbles = null

	# The health bar: a strip in the side's colour floating over the ship, facing the camera.
	var strip := QuadMesh.new()
	strip.size = Vector2(length * 0.3, length * 0.016)
	_bar_paint = ShaderMaterial.new()
	_bar_paint.shader = BarShader
	_bar_paint.set_shader_parameter("tint", LIVERY[faction][1])
	_bar = MeshInstance3D.new()
	_bar.mesh = strip
	_bar.material_override = _bar_paint
	_bar.position = Vector3(0, _half_h * 2.7, -length * 0.05)
	_bar.extra_cull_margin = length * 0.3
	_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bar)


## A shell has reached the hull at a world position.
func take_hit(amount: float, at: Vector3) -> void:
	if down:
		return
	health = maxf(health - amount, 0.0)
	_bar_paint.set_shader_parameter("fill", health / max_health)
	# Every quarter of its health gone leaves a hole that smokes from then on.
	while _wounds.size() < int((1.0 - health / max_health) * 4.0):
		_wounds.append(to_local(at))
	if health <= 0.0:
		_go_down()


func _go_down() -> void:
	down = true
	losses += 1
	_fall = 0.0
	_fall_speed = 0.0
	_next_blast = 0.3
	_bar.visible = false
	if flak:
		flak.burst(global_position, length * 0.03)


## Whole again and back in the line: at once, or coming down from high above.
func revive(from_above: bool = false) -> void:
	down = false
	health = max_health
	_wounds.clear()
	_lean = Vector2.ZERO
	_fall = 0.0
	_drop = ARRIVE_HEIGHT if from_above else 0.0
	visible = true
	_bar.visible = true
	_bar_paint.set_shader_parameter("fill", 1.0)
	position.y = cruise_y + _drop
	reset_physics_interpolation()


## Falling: nose down, rolling over, blowing up along its length, then gone, then replaced.
func _sink(delta: float) -> void:
	_fall += delta
	if _fall > SINK_TIME + AWAY_TIME:
		revive(true)
		return
	if not visible:
		return
	_fall_speed = minf(_fall_speed + 4.5 * delta, 38.0)
	_drop -= _fall_speed * delta
	_lean = _lean.lerp(Vector2(-0.38, 0.6 * _list), 1.0 - exp(-0.45 * delta))
	_next_blast -= delta
	if _next_blast <= 0.0 and flak:
		_next_blast = randf_range(0.25, 0.8)
		var where := Vector3(randf_range(-1.0, 1.0) * _half_w, randf_range(-0.4, 1.0) * _half_h, randf_range(-0.42, 0.42) * length)
		flak.burst(global_transform * where, length * randf_range(0.012, 0.026))
	if _fall > SINK_TIME or position.y < floor_y + _half_h:
		if position.y < floor_y + _half_h * 2.0 and flak:
			flak.burst(global_position, length * 0.035)
		visible = false


func _hull_shape(t: float) -> Vector3:
	# A blunt round bow, a long full belly, then a taper to a thick tail boom.
	var r: float = 1.0
	if t < 0.2:
		var back: float = 1.0 - t / 0.2
		r = maxf(sqrt(1.0 - back * back), 0.03)
	else:
		r = lerpf(1.0, 0.24, smoothstep(0.48, 1.0, t))
	# The keel sweeps up toward the tail.
	return Vector3(_half_w * r, _half_h * r, _half_h * 0.55 * t * t)


func _flat(_a: float) -> float:
	return 0.0


func _add_wing(at: Vector3, half_span: float, root: float, tip: float, sweep: float, engines: int) -> void:
	var rise := func(a: float) -> float: return a * half_span * 0.05
	var wing := MeshInstance3D.new()
	wing.mesh = MeshKit.wing(half_span, root, tip, sweep, 0.15, rise, 10, 6)
	wing.material_override = _metal
	wing.position = at
	add_child(wing)
	var mid_z: float = at.z + root * 0.1 + sweep * 0.5
	_capsules.append([Vector3(-half_span, at.y, mid_z), Vector3(half_span, at.y, mid_z), maxf(root * 0.09, 3.0)])

	for i in engines:
		var out: float = lerpf(0.42, 0.78, float(i) / maxf(float(engines - 1), 1.0))
		for side: float in [-1.0, 1.0]:
			var chord: float = lerpf(root, tip, pow(out, 1.2))
			var lead: float = -root * 0.4 + sweep * pow(out, 1.4)
			var radius: float = length * 0.013
			var pod_front := Vector3(out * half_span * side, at.y + out * half_span * 0.05, at.z + lead - chord * 0.25)
			add_child(MeshKit.rod(pod_front, pod_front + Vector3(0, 0, chord * 0.9), radius, _dark))
			_add_propeller(pod_front + Vector3(0, 0, -radius * 1.3), radius * 3.6)


func _add_propeller(at: Vector3, radius: float) -> void:
	var prop := Node3D.new()
	prop.position = at
	add_child(prop)
	for i in 3:
		var blade := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(radius * 0.16, radius, radius * 0.04)
		blade.mesh = box
		blade.material_override = _dark
		blade.transform = Transform3D(Basis(Vector3.BACK, TAU * float(i) / 3.0), Vector3.ZERO).translated_local(Vector3(0, radius * 0.5, 0))
		prop.add_child(blade)
	_props.append(prop)


func _add_bridge() -> void:
	# A gondola under the nose, with a lit strip of windows along each side and across the front.
	var size := Vector3(_half_w * 0.5, _half_h * 0.22, length * 0.12)
	var shape := func(t: float) -> Vector3:
		var r: float = maxf(pow(sin(PI * pow(t, 0.7)), 0.4), 0.05)
		return Vector3(size.x * r, size.y * r, 0.0)
	# The hull's underside is flattened to 0.85 of its half height (see build()).
	var at := Vector3(0, _hull_shape(0.24).z - _half_h * 0.85 - size.y * 0.4, -length * 0.26)
	var gondola := MeshInstance3D.new()
	gondola.mesh = MeshKit.body(size.z, shape, 14, 12, 3.2)
	gondola.material_override = _metal
	gondola.position = at
	add_child(gondola)
	for side: float in [-1.0, 1.0]:
		var strip := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.3, size.y * 0.42, size.z * 0.5)
		strip.mesh = box
		strip.material_override = _glass
		strip.position = at + Vector3(size.x * 0.97 * side, size.y * 0.1, -size.z * 0.05)
		add_child(strip)


## A place on the hull's skin: the origin is on it and +Y points out of it. `t` runs nose to
## tail, `ang` round the hull from the top (0) down the starboard side (+) or the port side (-).
func _skin(t: float, ang: float) -> Transform3D:
	var shape: Vector3 = _hull_shape(t)
	var c: float = sin(ang)
	var s: float = cos(ang)
	var e: float = 2.0 / HULL_POWER
	var tall: float = shape.y * (HULL_BELLY if s < 0.0 else 1.0)
	var at := Vector3(signf(c) * pow(absf(c), e) * shape.x, shape.z + signf(s) * pow(absf(s), e) * tall, lerpf(-0.5, 0.5, t) * length)
	var out := Vector3(signf(c) * pow(absf(c), 2.0 - e) / shape.x, signf(s) * pow(absf(s), 2.0 - e) / tall, 0.0).normalized()
	return Transform3D(Basis(out.cross(Vector3.BACK), out, Vector3.BACK), at)


func _box(into: SurfaceTool, size: Vector3, at: Transform3D) -> void:
	var box := BoxMesh.new()
	box.size = size
	into.append_from(box, 0, at)


## A round bar or drum from one point to another.
func _tube(into: SurfaceTool, from: Vector3, to: Vector3, radius: float, sides: int = 8) -> void:
	var drum := CylinderMesh.new()
	drum.top_radius = radius
	drum.bottom_radius = radius
	drum.height = from.distance_to(to)
	drum.radial_segments = sides
	drum.rings = 1
	var dir: Vector3 = (to - from).normalized()
	var side: Vector3 = dir.cross(Vector3.RIGHT if absf(dir.x) < 0.9 else Vector3.UP).normalized()
	into.append_from(drum, 0, Transform3D(Basis(side, dir, side.cross(dir)), (from + to) * 0.5))


## A glass bubble set into the hull at `seat`, in a bolted collar with two frame hoops over it.
## Returns the middle of the bubble.
func _add_bubble(seat: Transform3D, radius: float) -> Vector3:
	var out: Vector3 = seat.basis.y
	var centre: Vector3 = seat.origin - out * radius * 0.25
	var ball := SphereMesh.new()
	ball.radius = radius
	ball.height = radius * 2.0
	ball.radial_segments = 14
	ball.rings = 8
	_bubbles.append_from(ball, 0, Transform3D(Basis.IDENTITY, centre))
	_tube(_fittings, seat.origin - out * radius * 0.5, seat.origin + out * radius * 0.12, radius * 1.16, 14)
	var hoop := TorusMesh.new()
	hoop.inner_radius = radius * 0.96
	hoop.outer_radius = radius * 1.06
	hoop.rings = 18
	hoop.ring_segments = 5
	for turn: Vector3 in [Vector3.RIGHT, Vector3.BACK]:
		_fittings.append_from(hoop, 0, Transform3D(seat.basis * Basis(turn, PI * 0.5), centre))
	return centre


func _add_turrets(rng: RandomNumberGenerator) -> void:
	# The working guns: bubbles along the back, on the spine and on either shoulder by turns.
	var count: int = 3 + rng.randi() % 3
	for i in count:
		var t: float = lerpf(0.52, 0.86, float(i) / float(count - 1))
		var radius: float = length * 0.017
		var centre: Vector3 = _add_bubble(_skin(t, [0.0, 0.62, -0.62][i % 3]), radius)
		# The gun: a pivot inside the bubble with twin barrels along its -Z, out through the glass.
		var gun := Node3D.new()
		gun.position = centre
		gun.basis = Basis.looking_at(Vector3(rng.randf_range(-0.5, 0.5), 0.35, -1.0).normalized(), Vector3.UP)
		add_child(gun)
		for side: float in [-1.0, 1.0]:
			var from := Vector3(radius * 0.28 * side, 0, 0)
			gun.add_child(MeshKit.rod(from, from + Vector3(0, 0, -radius * 2.1), radius * 0.09, _dark))
		_turrets.append([gun, rng.randf_range(1.0, 4.0), radius * 2.3])
	# Smaller blisters down each flank, their guns fixed pointing out.
	for i in 3:
		for side: float in [-1.0, 1.0]:
			var seat: Transform3D = _skin(0.3 + 0.15 * float(i), 1.32 * side)
			var radius: float = length * 0.012
			var centre: Vector3 = _add_bubble(seat, radius)
			for gap: float in [-1.0, 1.0]:
				var from: Vector3 = centre + Vector3(0, 0, radius * 0.3 * gap)
				_tube(_fittings, from, from + (seat.basis.y + Vector3(0, -0.15, 0)).normalized() * radius * 2.0, radius * 0.1, 6)


## Everything bolted to the outside: ribs round the hull, pipes along it, housings, stacks, masts.
func _add_fittings(rng: RandomNumberGenerator) -> void:
	var u: float = length * 0.01
	# Ribs: hoops of flat bar over the back and down both flanks.
	for i in 7:
		var t: float = lerpf(0.2, 0.84, float(i) / 6.0)
		var last: Transform3D = _skin(t, -2.2)
		for j in range(1, 15):
			var next: Transform3D = _skin(t, lerpf(-2.2, 2.2, float(j) / 14.0))
			var along: Vector3 = next.origin - last.origin
			var out: Vector3 = (last.basis.y + next.basis.y).normalized()
			var across: Vector3 = along.normalized()
			_box(_fittings, Vector3(along.length() * 1.08, u * 0.5, u * 0.75),
					Transform3D(Basis(across, Vector3.BACK.cross(across), Vector3.BACK), (last.origin + next.origin) * 0.5 + out * u * 0.05))
			last = next
	# Pipes: long runs standing just off the plating.
	for ang: float in [1.05, -1.05, 1.62, -1.62]:
		var from_t: float = rng.randf_range(0.2, 0.3)
		var to_t: float = rng.randf_range(0.66, 0.82)
		var last: Vector3 = Vector3.ZERO
		for j in 11:
			var seat: Transform3D = _skin(lerpf(from_t, to_t, float(j) / 10.0), ang)
			var at: Vector3 = seat.origin + seat.basis.y * u * 0.35
			if j > 0:
				_tube(_fittings, last, at, u * 0.3, 6)
			last = at
	# Housings: boxes of all sizes sunk into the skin.
	for i in 18:
		var seat: Transform3D = _skin(rng.randf_range(0.2, 0.86), rng.randf_range(0.5, 1.9) * (1.0 if i % 2 == 0 else -1.0))
		var size := Vector3(rng.randf_range(1.0, 3.0), rng.randf_range(0.7, 1.5), rng.randf_range(1.6, 5.5)) * u
		_box(_fittings, size, seat.translated_local(Vector3(0, size.y * 0.15, 0)))
		if rng.randf() < 0.5:
			# A drum or a hatch on top of it.
			var top: Vector3 = seat.origin + seat.basis.y * size.y * 0.6
			_tube(_fittings, top, top + seat.basis.y * u * rng.randf_range(0.3, 0.9), minf(size.x, size.z) * 0.32, 10)
	# Fat pods hung on pylons under the flanks.
	var pod_shape := func(t: float) -> Vector3:
		var r: float = maxf(pow(sin(PI * pow(t, 0.6)), 0.55), 0.06)
		return Vector3(u * 2.3 * r, u * 2.3 * r, 0.0)
	for i in 2 + rng.randi() % 2:
		for side: float in [-1.0, 1.0]:
			var seat: Transform3D = _skin(0.3 + 0.17 * float(i), 2.25 * side)
			var hang: Vector3 = seat.origin + Vector3(side * u * 1.5, -u * 4.5, 0)
			var pod := MeshInstance3D.new()
			pod.mesh = MeshKit.body(u * 14.0, pod_shape, 10, 10)
			pod.material_override = _metal
			pod.position = hang
			add_child(pod)
			for z: float in [-u * 2.5, u * 2.5]:
				_tube(_fittings, seat.origin + Vector3(0, u, z), hang + Vector3(0, 0, z), u * 0.45, 6)
	# Stacks along the shoulders, and thin masts.
	for i in 4:
		var seat: Transform3D = _skin(rng.randf_range(0.28, 0.48), 0.78 * (1.0 if i % 2 == 0 else -1.0))
		_tube(_fittings, seat.origin - Vector3(0, u, 0), seat.origin + Vector3(0, u * rng.randf_range(2.0, 3.6), 0), u * rng.randf_range(0.6, 0.9), 10)
	for t: float in [0.16, 0.93]:
		var seat: Transform3D = _skin(t, 0.0)
		_tube(_fittings, seat.origin, seat.origin + Vector3(0, u * rng.randf_range(6.0, 10.0), 0), u * 0.13, 5)


func _process(delta: float) -> void:
	if not visible:
		return
	for prop: Node3D in _props:
		prop.rotate_object_local(Vector3.BACK, delta * 14.0)
	_pour_smoke(delta)
	_work_guns(delta)


## Dark smoke from every hole, and flames too once it is nearly done for.
func _pour_smoke(delta: float) -> void:
	if flak == null or _wounds.is_empty():
		return
	_smoke -= delta
	if _smoke > 0.0:
		return
	_smoke = 0.5 / float(_wounds.size())
	var from: Vector3 = global_transform * (_wounds[randi() % _wounds.size()] as Vector3)
	flak.smoke(from, length * randf_range(0.022, 0.04), down or health < max_health * 0.3)


func _work_guns(delta: float) -> void:
	if flak == null or down:
		return
	var shell_speed: float = flak.SHELL_SPEED
	var to_ship: Basis = global_basis.inverse()
	# The glider, if she is near enough to bother with.
	var glider_near: bool = target != null and global_position.distance_to(target.global_position) < GUN_RANGE + length
	# And the nearest enemy ship.
	var foe: Node3D = null
	var foe_away: float = FOE_RANGE
	for other: Node3D in foes:
		if other.down:
			continue
		var away: float = global_position.distance_to(other.global_position)
		if away < foe_away:
			foe_away = away
			foe = other
	if not glider_near and foe == null:
		return
	for i in _turrets.size():
		var turret: Array = _turrets[i]
		var gun: Node3D = turret[0]
		var from: Vector3 = gun.global_position
		turret[1] = (turret[1] as float) - delta
		# The war comes first. One gun in three is a flak gun that turns on her if she is close.
		var mark := Vector3.ZERO
		var mark_velocity := Vector3.ZERO
		var at_ship := false
		if i % 3 == 0 and glider_near and from.distance_to(target.global_position) < GUN_RANGE:
			mark = target.global_position
			mark_velocity = target.velocity
		elif foe != null:
			# Each gun has its own stretch of the enemy's hull to pound.
			var along: float = lerpf(-0.3, 0.3, float(i) / float(_turrets.size() - 1))
			mark = foe.global_transform * Vector3(0, foe.length * 0.03, along * (foe.length as float))
			mark_velocity = -foe.global_basis.z * (foe.speed as float)
			at_ship = true
		else:
			continue
		# Aim where it will be when the shell gets there.
		var flight: float = from.distance_to(mark) / shell_speed
		var ahead: Vector3 = mark + mark_velocity * flight
		flight = from.distance_to(ahead) / shell_speed
		var aim: Vector3 = (to_ship * (ahead - from)).normalized()
		# The guns cannot point down through their own deck (a ship a little lower they can reach).
		if aim.y < (-0.25 if at_ship else -0.06) or aim.y > 0.97:
			continue
		gun.basis = gun.basis.orthonormalized().slerp(Basis.looking_at(aim, Vector3.UP), 1.0 - exp(-2.5 * delta))
		if armed and (turret[1] as float) <= 0.0 and (-gun.basis.z).dot(aim) > 0.996:
			# Ship against ship is wilder fire, fused long so it carries to the hull (or past it).
			turret[1] = randf_range(1.6, 3.2) if at_ship else randf_range(2.0, 3.6)
			var spread: float = GUN_SPREAD * (2.0 if at_ship else 1.0)
			var wild := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * spread
			var dir: Vector3 = (global_basis * (aim + wild)).normalized()
			var fuse: float = flight * (randf_range(1.05, 1.3) if at_ship else randf_range(0.94, 1.05))
			if not at_ship:
				shots_at_glider += 1
			flak.fire(from + dir * (turret[2] as float), dir * shell_speed, fuse, faction)


func _physics_process(delta: float) -> void:
	_time += delta
	if down:
		_sink(delta)
	elif _drop > 0.0:
		# A fresh ship settling down into the line.
		_drop = maxf(_drop * exp(-0.3 * delta) - 2.0 * delta, 0.0)
	# (A falling ship keeps its way on, so its place in the line is still where it would be.)
	var forward := Vector3(-sin(heading), 0.0, -cos(heading))
	position += forward * speed * delta
	position.y = cruise_y + sin(_time * 0.21 + _phase) * 5.0 + _drop
	rotation = Vector3(sin(_time * 0.17 + _phase) * 0.012 + _lean.x, heading, sin(_time * 0.13 + _phase * 2.0) * 0.02 + _lean.y)


## If a ball at a world position overlaps the ship, returns the shortest push (world space)
## that gets it out. Vector3.ZERO means no contact.
func hit(world: Vector3, radius: float) -> Vector3:
	if not visible:
		return Vector3.ZERO
	var p: Vector3 = to_local(world)
	if p.length() > length * 0.7:
		return Vector3.ZERO
	# The hull: an oval around the keel line whose size follows the same profile as the mesh.
	var t: float = p.z / length + 0.5
	if t > 0.0 and t < 1.0:
		var shape: Vector3 = _hull_shape(t)
		var off := Vector2(p.x / shape.x, (p.y - shape.z) / shape.y)
		var reach: float = 1.0 + radius / shape.y
		var d: float = off.length()
		if d < reach:
			var n := Vector3(off.x / shape.x, off.y / shape.y, 0.0)
			if n.length() < 0.0001:
				n = Vector3.UP
			return global_basis * (n.normalized() * (reach - d) * shape.y)
	for c: Array in _capsules:
		var nearest: Vector3 = Geometry3D.get_closest_point_to_segment(p, c[0], c[1])
		var away: Vector3 = p - nearest
		var reach: float = float(c[2]) + radius
		if away.length() < reach:
			if away.length() < 0.0001:
				away = Vector3.UP
			return global_basis * (away.normalized() * (reach - away.length()))
	return Vector3.ZERO
