extends Node3D
## One giant metal airship, built in code: a riveted hull with slab wings, propeller engines,
## a twin tail, a bridge slung under the nose and gun turrets along its back. `build()` takes a
## length and a seed, so every ship in a fleet comes out a different size and cut.
##
## It cruises straight ahead (-Z) with a slow heave. `hit()` tells the glider when it has flown
## into the hull or a wing and which way to push it back out.
##
## Its turrets fire shells through `flak` while `armed`: at `target` (the glider) when she is in
## range, otherwise at the nearest of `foes` (the other side's ships). They lead what they shoot
## at, so flying straight gets you hit and turning does not. The guns sit along the back of
## the ship and cannot point down past the deck: underneath a ship is out of their sight.

const MeshKit := preload("res://scripts/mesh_kit.gd")
const HullShader := preload("res://shaders/hull.gdshader")
const Toon := preload("res://scripts/toon.gd")

## Each side's colours: [hull paints to pick from, the stripe].
const LIVERY := [
	[[Color(0.33, 0.37, 0.43), Color(0.27, 0.33, 0.36), Color(0.4, 0.42, 0.45)], Color(0.85, 0.68, 0.2)],
	[[Color(0.5, 0.25, 0.18), Color(0.43, 0.3, 0.2), Color(0.38, 0.2, 0.17)], Color(0.9, 0.86, 0.76)],
]

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

const GUN_RANGE := 1100.0
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
var _time := 0.0
var _phase := 0.0


func build(ship_length: float, ship_seed: int, faction: int = 0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = ship_seed
	length = ship_length
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

	var hull := MeshInstance3D.new()
	hull.mesh = MeshKit.body(length, _hull_shape, 32, 36, 3.2, 0.85)
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


func _add_turrets(rng: RandomNumberGenerator) -> void:
	var count: int = 3 + rng.randi() % 3
	for i in count:
		var t: float = lerpf(0.52, 0.86, float(i) / float(count - 1))
		var shape: Vector3 = _hull_shape(t)
		var at := Vector3(0, shape.z + shape.y * 0.97, lerpf(-0.5, 0.5, t) * length)
		var radius: float = length * 0.014
		var dome := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = radius
		ball.height = radius * 2.0
		ball.radial_segments = 12
		ball.rings = 6
		dome.mesh = ball
		dome.material_override = _metal
		dome.position = at
		add_child(dome)
		# The gun: a pivot in the dome with twin barrels along its -Z.
		var gun := Node3D.new()
		gun.position = at + Vector3(0, radius * 0.4, 0)
		gun.basis = Basis.looking_at(Vector3(rng.randf_range(-0.5, 0.5), 0.35, -1.0).normalized(), Vector3.UP)
		add_child(gun)
		for side: float in [-1.0, 1.0]:
			var from := Vector3(radius * 0.3 * side, 0, 0)
			gun.add_child(MeshKit.rod(from, from + Vector3(0, 0, -radius * 2.6), radius * 0.09, _dark))
		_turrets.append([gun, rng.randf_range(1.0, 4.0), radius * 2.8])


func _process(delta: float) -> void:
	for prop: Node3D in _props:
		prop.rotate_object_local(Vector3.BACK, delta * 14.0)
	_work_guns(delta)


func _work_guns(delta: float) -> void:
	if flak == null:
		return
	var shell_speed: float = flak.SHELL_SPEED
	var to_ship: Basis = global_basis.inverse()
	# The glider, if she is near enough to bother with.
	var glider_near: bool = target != null and global_position.distance_to(target.global_position) < GUN_RANGE + length
	# And the nearest enemy ship.
	var foe: Node3D = null
	var foe_away: float = FOE_RANGE
	for other: Node3D in foes:
		var away: float = global_position.distance_to(other.global_position)
		if away < foe_away:
			foe_away = away
			foe = other
	if not glider_near and foe == null:
		return
	for turret: Array in _turrets:
		var gun: Node3D = turret[0]
		var from: Vector3 = gun.global_position
		turret[1] = (turret[1] as float) - delta
		# She comes first; otherwise the enemy ship.
		var mark := Vector3.ZERO
		var mark_velocity := Vector3.ZERO
		var at_ship := false
		if glider_near and from.distance_to(target.global_position) < GUN_RANGE:
			mark = target.global_position
			mark_velocity = target.velocity
		elif foe != null:
			mark = foe.global_position + Vector3(0, foe.length * 0.03, 0)
			mark_velocity = -foe.global_basis.z * (foe.speed as float)
			at_ship = true
		else:
			continue
		# Aim where it will be when the shell gets there.
		var flight: float = from.distance_to(mark) / shell_speed
		var ahead: Vector3 = mark + mark_velocity * flight
		flight = from.distance_to(ahead) / shell_speed
		var aim: Vector3 = (to_ship * (ahead - from)).normalized()
		# The guns cannot point down through their own deck.
		if aim.y < -0.06 or aim.y > 0.97:
			continue
		gun.basis = gun.basis.orthonormalized().slerp(Basis.looking_at(aim, Vector3.UP), 1.0 - exp(-2.5 * delta))
		if armed and (turret[1] as float) <= 0.0 and (-gun.basis.z).dot(aim) > 0.996:
			# Ship against ship is slower, wilder fire, fused to burst just short of the hull.
			turret[1] = randf_range(3.0, 6.0) if at_ship else randf_range(2.0, 3.6)
			var spread: float = GUN_SPREAD * (2.5 if at_ship else 1.0)
			var wild := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * spread
			var dir: Vector3 = (global_basis * (aim + wild)).normalized()
			var fuse: float = flight * (randf_range(0.84, 0.97) if at_ship else randf_range(0.94, 1.05))
			flak.fire(from + dir * (turret[2] as float), dir * shell_speed, fuse)


func _physics_process(delta: float) -> void:
	_time += delta
	var forward := Vector3(-sin(heading), 0.0, -cos(heading))
	position += forward * speed * delta
	position.y = cruise_y + sin(_time * 0.21 + _phase) * 5.0
	rotation = Vector3(sin(_time * 0.17 + _phase) * 0.012, heading, sin(_time * 0.13 + _phase * 2.0) * 0.02)


## If a ball at a world position overlaps the ship, returns the shortest push (world space)
## that gets it out. Vector3.ZERO means no contact.
func hit(world: Vector3, radius: float) -> Vector3:
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
