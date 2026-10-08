extends Node3D
## The fleet's gunfire: the shells in the air, and the explosions they end in.
##
## Every shell is fused to burst about where its gunner expected the glider to be, so a shot that
## misses goes off near her in a cartoon puff-ball explosion (shaders/burst, after The Wind
## Waker): a star flash, then a cluster of curled cloud puffs that swell, cool and hollow out.
## A shell that passes close enough before its fuse runs out is a hit. A burst close by only
## throws her about.
##
## Shells and puffs are each drawn as one MultiMesh.

const BurstShader := preload("res://shaders/burst.gdshader")

const SHELL_SPEED := 190.0
const HIT_RADIUS := 2.8
## A burst nearer than this shoves the glider.
const BLAST_RADIUS := 18.0
const MAX_SHELLS := 160
const MAX_PUFFS := 320

## The glider. Needs take_hit(push) and shove(push).
var target: Node3D

# For the tests.
var shots_fired := 0
var bursts := 0
var hits := 0
var closest := INF

var _shells: Array = []  # each [Vector3 position, Vector3 velocity, float fuse]
var _puffs: Array = []  # each [Vector3 position, Vector3 velocity, float age, float life, float size, float seed, float kind, float spin]
var _shell_mm := MultiMesh.new()
var _puff_mm := MultiMesh.new()


func _ready() -> void:
	# Everything here is moved every frame, in world space.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var everywhere := AABB(Vector3.ONE * -100000.0, Vector3.ONE * 200000.0)

	var tracer := BoxMesh.new()
	tracer.size = Vector3(0.45, 0.45, 7.0)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.82, 0.35)
	_shell_mm.transform_format = MultiMesh.TRANSFORM_3D
	_shell_mm.mesh = tracer
	_shell_mm.instance_count = MAX_SHELLS
	_shell_mm.visible_instance_count = 0
	var shells := MultiMeshInstance3D.new()
	shells.multimesh = _shell_mm
	shells.material_override = glow
	shells.custom_aabb = everywhere
	shells.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shells)

	var card := QuadMesh.new()
	card.size = Vector2(2.0, 2.0)
	var paint := ShaderMaterial.new()
	paint.shader = BurstShader
	_puff_mm.transform_format = MultiMesh.TRANSFORM_3D
	_puff_mm.use_custom_data = true
	_puff_mm.mesh = card
	_puff_mm.instance_count = MAX_PUFFS
	_puff_mm.visible_instance_count = 0
	var puffs := MultiMeshInstance3D.new()
	puffs.multimesh = _puff_mm
	puffs.material_override = paint
	puffs.custom_aabb = everywhere
	puffs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(puffs)


## Send a shell on its way. It bursts when `fuse` seconds are up.
func fire(origin: Vector3, velocity: Vector3, fuse: float) -> void:
	if _shells.size() >= MAX_SHELLS:
		return
	_shells.append([origin, velocity, fuse])
	shots_fired += 1


## An explosion: one flash and a cluster of puffs thrown outward.
func burst(at: Vector3, size: float = 1.0) -> void:
	bursts += 1
	_add_puff(at, Vector3.ZERO, 0.16, 9.0 * size, 1.0)
	for i in 6:
		var out := Vector3(randf_range(-1.0, 1.0), randf_range(-0.7, 1.0), randf_range(-1.0, 1.0)).normalized()
		_add_puff(at + out * 2.0 * size, out * randf_range(7.0, 15.0) * size, randf_range(0.9, 1.5),
				randf_range(2.6, 4.4) * size, 0.0)
	if target and target.global_position.distance_to(at) < BLAST_RADIUS * size:
		var away: Vector3 = target.global_position - at
		target.shove(away.normalized() * 5.0 * (1.0 - away.length() / (BLAST_RADIUS * size)))


func _add_puff(at: Vector3, velocity: Vector3, life: float, size: float, kind: float) -> void:
	if _puffs.size() >= MAX_PUFFS:
		_puffs.pop_front()
	_puffs.append([at, velocity, 0.0, life, size, randf(), kind, randf_range(-1.5, 1.5)])


func _process(delta: float) -> void:
	var mark := Vector3.INF
	if target:
		mark = target.global_position

	var alive: Array = []
	for shell: Array in _shells:
		var from: Vector3 = shell[0]
		var to: Vector3 = from + (shell[1] as Vector3) * delta
		shell[0] = to
		shell[2] = (shell[2] as float) - delta
		if mark != Vector3.INF:
			var near: float = Geometry3D.get_closest_point_to_segment(mark, from, to).distance_to(mark)
			closest = minf(closest, near)
			if near < HIT_RADIUS:
				hits += 1
				burst(mark, 0.6)
				target.take_hit((shell[1] as Vector3).normalized() * 7.0)
				continue
		if (shell[2] as float) <= 0.0:
			burst(to)
			continue
		alive.append(shell)
	_shells = alive

	_shell_mm.visible_instance_count = _shells.size()
	for i in _shells.size():
		var along: Vector3 = (_shells[i][1] as Vector3).normalized()
		var up := Vector3.UP if absf(along.y) < 0.95 else Vector3.RIGHT
		_shell_mm.set_instance_transform(i, Transform3D(Basis.looking_at(along, up), _shells[i][0]))

	var smoking: Array = []
	for puff: Array in _puffs:
		puff[2] = (puff[2] as float) + delta / (puff[3] as float)
		if (puff[2] as float) >= 1.0:
			continue
		# Thrown out fast, then hanging and drifting up.
		puff[1] = (puff[1] as Vector3) * exp(-3.5 * delta) + Vector3.UP * 1.2 * delta
		puff[0] = (puff[0] as Vector3) + (puff[1] as Vector3) * delta
		smoking.append(puff)
	_puffs = smoking

	_puff_mm.visible_instance_count = _puffs.size()
	for i in _puffs.size():
		var puff: Array = _puffs[i]
		var age: float = puff[2]
		# Swell quickly, then keep growing slowly.
		var size: float = (puff[4] as float) * (0.35 + 0.65 * (1.0 - pow(1.0 - minf(age * 3.0, 1.0), 3.0)) + age * 0.35)
		_puff_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * size), puff[0]))
		_puff_mm.set_instance_custom_data(i, Color(age, puff[5], puff[6], puff[7]))
