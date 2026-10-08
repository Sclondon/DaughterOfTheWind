extends Node3D
## The fighters: small H-shaped gliders flown by each side's pilots. Two long booms joined by a
## wing, with a pod in the middle under a glass canopy where the pilot sits.
##
## They are not flown with the glider's flight model, just steered: each has a speed and may turn
## only so fast. A fighter picks something to chase (the glider if she is near, otherwise one of
## the other side's fighters), turns onto it, fires bolts when it is lined up and close, then
## breaks away and comes round again. With nothing to chase it circles its own fleet. They keep
## clear of the ground, the sea and the big ships. Fighters shoot each other down too; one that
## is hit goes up in a burst and a fresh one launches from its fleet a little later.

const MeshKit := preload("res://scripts/mesh_kit.gd")
const Toon := preload("res://scripts/toon.gd")
const Trail := preload("res://scripts/trail.gd")

const PER_SIDE := 4
const CRUISE := 38.0
const CHASE := 46.0
const TURN_RATE := 1.0
## How near the glider has to be before fighters go for her, and how near anything has to be,
## and how well lined up, before they fire.
const NOTICE := 1300.0
const GUN_REACH := 340.0
const GUN_CONE := 0.09
## What each side is painted: [hull, trim].
const LIVERY := [
	[Color(0.3, 0.38, 0.5), Color(0.9, 0.75, 0.25)],
	[Color(0.6, 0.24, 0.16), Color(0.92, 0.88, 0.78)],
]

## The glider, the two fleets, the shared flak, and (optionally) the land, for its height_at().
var focus: Node3D
var fleets: Array = []
var flak: Node3D
var land: Node
## False stops them firing (they still fly).
var armed := true

var fighters: Array = []
## Fighters shot down so far, for the tests.
var losses := 0


class Fighter:
	var node: Node3D
	var side := 0
	var velocity := Vector3.FORWARD * 38.0
	var prey  # the glider, another Fighter, or null
	var think := 0.0  # seconds until it reconsiders what to chase
	var breaking := 0.0  # seconds left of breaking away
	var break_way := Vector3.ZERO
	var reload := 0.0
	var burst := 0  # bolts left in this burst
	var down := 0.0  # seconds until it launches again (0 = flying)
	var roll := 0.0
	var slot := 0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for side in 2:
		for i in PER_SIDE:
			var fighter := Fighter.new()
			fighter.side = side
			fighter.slot = i
			fighter.node = _build(side)
			add_child(fighter.node)
			fighters.append(fighter)
			_launch(fighter)


## Set a fighter flying beside its own flagship.
func _launch(fighter: Fighter) -> void:
	fighter.down = 0.0
	fighter.prey = null
	fighter.think = randf()
	if fleets.size() < 2:
		return
	var home: Node3D = fleets[fighter.side].ships[fighter.slot % fleets[fighter.side].ships.size()]
	var forward: Vector3 = -home.global_basis.z
	fighter.node.position = home.position + Vector3(randf_range(-80.0, 80.0), 70.0 + fighter.slot * 25.0, randf_range(-80.0, 80.0))
	fighter.velocity = forward * CRUISE
	fighter.node.visible = true


## Everything sent back to its fleet (after the battle has moved).
func regroup() -> void:
	for fighter: Fighter in fighters:
		_launch(fighter)


func _process(delta: float) -> void:
	if fleets.size() < 2:
		return
	for fighter: Fighter in fighters:
		if fighter.down > 0.0:
			fighter.down -= delta
			if fighter.down <= 0.0:
				_launch(fighter)
			continue
		_fly(fighter, delta)


func _fly(fighter: Fighter, delta: float) -> void:
	var at: Vector3 = fighter.node.position
	var heading: Vector3 = fighter.velocity.normalized()
	fighter.think -= delta
	fighter.reload -= delta
	if fighter.think <= 0.0:
		fighter.think = randf_range(0.8, 1.6)
		fighter.prey = _choose(fighter)

	# Where does it want to go?
	var want: Vector3 = heading
	var speed: float = CRUISE
	if fighter.breaking > 0.0:
		fighter.breaking -= delta
		want = fighter.break_way
	elif fighter.prey != null:
		var prey_at: Vector3 = _where(fighter.prey)
		var prey_velocity: Vector3 = _velocity_of(fighter.prey)
		var away: float = at.distance_to(prey_at)
		# Lead it a little.
		want = (prey_at + prey_velocity * minf(away / 190.0, 1.5) - at).normalized()
		speed = CHASE
		var lined_up: bool = heading.dot((prey_at - at).normalized()) > 1.0 - GUN_CONE
		if armed and lined_up and away < GUN_REACH and fighter.reload <= 0.0:
			fighter.burst = 3
		if away < 70.0:
			# Too close: peel off up and to one side, and come round again.
			fighter.breaking = randf_range(2.0, 3.5)
			fighter.break_way = (heading + Vector3(randf_range(-1.0, 1.0), randf_range(0.2, 0.9), randf_range(-1.0, 1.0))).normalized()
	else:
		# Nothing to chase: circle above its own flagship.
		var home: Node3D = fleets[fighter.side].ships[0]
		var post: Vector3 = home.position + Vector3(0, 160.0 + fighter.slot * 40.0, 0)
		var out: Vector3 = at - post
		out.y = 0.0
		var round_it: Vector3 = Vector3.UP.cross(out).normalized()
		want = (round_it + (post + out.normalized() * 380.0 - at) * 0.004).normalized()

	if fighter.burst > 0 and fighter.reload <= 0.0:
		fighter.burst -= 1
		fighter.reload = 0.14 if fighter.burst > 0 else randf_range(1.6, 2.8)
		_shoot(fighter, at, heading)

	want = _keep_clear(at, want)

	# Turn toward it, only so fast, and bank into the turn.
	var axis: Vector3 = heading.cross(want)
	var off: float = heading.angle_to(want)
	if axis.length() > 0.0001 and off > 0.0001:
		heading = heading.rotated(axis.normalized(), minf(off, TURN_RATE * delta))
	var now: float = fighter.velocity.length()
	fighter.velocity = heading * lerpf(now, speed, 1.0 - exp(-1.5 * delta))
	at += fighter.velocity * delta
	var bank: float = clampf(-axis.y * 2.2, -1.2, 1.2) if off > 0.02 else 0.0
	fighter.roll = lerpf(fighter.roll, bank, 1.0 - exp(-4.0 * delta))
	var up := Vector3.UP if absf(heading.y) < 0.97 else Vector3.BACK
	fighter.node.transform = Transform3D(Basis.looking_at(heading, up) * Basis(Vector3.BACK, fighter.roll), at)


## What should this fighter chase? The glider if she is near; otherwise the nearest of the other
## side's fighters; otherwise nothing.
func _choose(fighter: Fighter):
	var at: Vector3 = fighter.node.position
	if focus:
		var away: float = at.distance_to(focus.global_position)
		# Half of them go for her from a long way off; the rest only if she comes close.
		if away < (NOTICE if fighter.slot % 2 == 0 else NOTICE * 0.4):
			return focus
	var nearest = null
	var best: float = 2600.0
	for other: Fighter in fighters:
		if other.side == fighter.side or other.down > 0.0:
			continue
		var away: float = at.distance_to(other.node.position)
		if away < best:
			best = away
			nearest = other
	return nearest


func _where(prey) -> Vector3:
	if prey is Fighter:
		return (prey as Fighter).node.position
	return (prey as Node3D).global_position


func _velocity_of(prey) -> Vector3:
	if prey is Fighter:
		return (prey as Fighter).velocity
	return (prey as Node3D).velocity


func _shoot(fighter: Fighter, at: Vector3, heading: Vector3) -> void:
	var wild := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 0.025
	var dir: Vector3 = (heading + wild).normalized()
	flak.fire(at + dir * 6.0, dir * flak.SHELL_SPEED, 1.9)
	# Fighter against fighter is decided by chance, not by tracking every bolt.
	if fighter.prey is Fighter and randf() < 0.05:
		var prey: Fighter = fighter.prey
		if prey.down <= 0.0:
			flak.burst(prey.node.position, 1.3)
			prey.node.visible = false
			prey.down = randf_range(6.0, 11.0)
			losses += 1
			fighter.prey = null


## Bend a wanted direction away from the ground, the sea and the big ships.
func _keep_clear(at: Vector3, want: Vector3) -> Vector3:
	var floor_y: float = 70.0
	if land:
		var ahead: Vector3 = at + want * 260.0
		floor_y = maxf(maxf(land.height_at(at.x, at.z), land.height_at(ahead.x, ahead.z)), 0.0) + 110.0
	if at.y < floor_y:
		want = (want + Vector3.UP * clampf((floor_y - at.y) / 60.0, 0.3, 3.0)).normalized()
	for fleet: Node3D in fleets:
		for ship: Node3D in fleet.ships:
			var off: Vector3 = at - ship.position
			var room: float = ship.length * 0.75
			if off.length() < room:
				want = (want + off.normalized() * 2.0 * (1.0 - off.length() / room) + Vector3.UP * 0.4).normalized()
	return want


## The H-shaped fighter: two booms, the wing joining them, tail fins, engines, and the pod with
## its glass canopy and the pilot's helmet inside. Forward is -Z.
func _build(side: int) -> Node3D:
	var hull: ShaderMaterial = Toon.paint(LIVERY[side][0], 9.0)
	var trim: ShaderMaterial = Toon.paint(LIVERY[side][1], 9.0)
	var dark: ShaderMaterial = Toon.paint(Color(0.12, 0.12, 0.14), 3.0)
	var glass: ShaderMaterial = Toon.glowing(Color(0.55, 0.8, 0.9), Color(0.12, 0.2, 0.24), 3.0)
	var burn: ShaderMaterial = Toon.glowing(Color(1.0, 0.6, 0.2), Color(2.0, 1.0, 0.3), 3.0)
	var node := Node3D.new()

	var boom_shape := func(t: float) -> Vector3:
		var r: float = maxf(pow(sin(PI * pow(t, 0.7)), 0.6), 0.08)
		return Vector3(0.42 * r, 0.46 * r, 0.0)
	for x: float in [-2.5, 2.5]:
		var boom := MeshInstance3D.new()
		boom.mesh = MeshKit.body(7.4, boom_shape, 10, 12)
		boom.material_override = hull
		boom.position = Vector3(x, 0, 0)
		node.add_child(boom)
		# A fin on the tail of each boom, and an engine glowing in it.
		var fin := MeshInstance3D.new()
		fin.mesh = MeshKit.slab(PackedFloat32Array([0.0, 0.3, 0.7, 1.1, 1.4]),
				func(s: float) -> Vector2: return Vector2(-0.5 + s * 0.45, 0.45 - s * 0.1), 0.1, 4)
		fin.material_override = trim
		fin.transform = Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(x, 0.25, 3.0))
		node.add_child(fin)
		node.add_child(MeshKit.rod(Vector3(x, 0, 3.55), Vector3(x, 0, 3.75), 0.2, burn))
		# The stub of wing outside each boom.
		var stub := MeshInstance3D.new()
		var outer: float = x + signf(x) * 1.5
		stub.mesh = MeshKit.slab(PackedFloat32Array([minf(x, outer), (x + outer) * 0.5, maxf(x, outer)]),
				func(s: float) -> Vector2: return Vector2(-0.55 + absf(absf(s) - 2.5) * 0.3, 0.6), 0.14, 5)
		stub.material_override = trim
		node.add_child(stub)

	# The crossbar of the H.
	var wing := MeshInstance3D.new()
	wing.mesh = MeshKit.slab(PackedFloat32Array([-2.5, -1.2, 0.0, 1.2, 2.5]),
			func(_s: float) -> Vector2: return Vector2(-0.85, 0.85), 0.2, 6)
	wing.material_override = hull
	node.add_child(wing)

	# The pod in the middle, with the canopy on top.
	var pod_shape := func(t: float) -> Vector3:
		var r: float = maxf(pow(sin(PI * pow(t, 0.65)), 0.7), 0.06)
		return Vector3(0.62 * r, 0.5 * r, 0.0)
	var pod := MeshInstance3D.new()
	pod.mesh = MeshKit.body(3.6, pod_shape, 12, 12)
	pod.material_override = hull
	pod.position = Vector3(0, 0.12, -0.3)
	node.add_child(pod)
	var dome := SphereMesh.new()
	dome.radius = 1.0
	dome.height = 2.0
	dome.radial_segments = 14
	dome.rings = 8
	var canopy := MeshInstance3D.new()
	canopy.mesh = dome
	canopy.material_override = glass
	canopy.scale = Vector3(0.46, 0.42, 0.95)
	canopy.position = Vector3(0, 0.5, -0.55)
	node.add_child(canopy)
	var helmet := MeshInstance3D.new()
	helmet.mesh = dome
	helmet.material_override = dark
	helmet.scale = Vector3.ONE * 0.2
	helmet.position = Vector3(0, 0.62, -0.5)
	node.add_child(helmet)
	# (The helmet shows as a dark shape through the top of the glass only from close by.)
	canopy.scale *= 0.98

	var trail: MeshInstance3D = Trail.new()
	trail.source = node
	trail.offset = Vector3(0, 0, 3.7)
	trail.strength = 0.45
	trail.width = 0.5
	trail.tint = LIVERY[side][1]
	node.add_child(trail)
	return node
