extends Node3D
## The airship fleet: a convoy of giant ships in a staggered V, crossing the sky on a straight
## course. When the glider has left them far behind, the convoy is set down again ahead of it on
## a new course, so there are always ships somewhere on the horizon.

const Airship := preload("res://scripts/airship.gd")
const Flak := preload("res://scripts/flak.gd")

## Where each ship flies relative to the flagship (x right, y up, z behind), and how long it is.
const FORMATION := [
	[Vector3(0, 0, 0), 320.0],
	[Vector3(-250, -40, 300), 210.0],
	[Vector3(270, 30, 330), 230.0],
	[Vector3(-520, 20, 640), 170.0],
	[Vector3(560, -50, 700), 180.0],
]
const LOST_DISTANCE := 7000.0
const SPEED := 13.0

var focus: Node3D
var ships: Array = []
var fleet_seed := 77
## The lowest and highest the convoy cruises when it comes round again.
var floor_y := 420.0
var ceiling_y := 900.0
## The shells and explosions of every gun in the fleet.
var flak: Node3D
## False holds fire (the guns still track).
var armed := true:
	set(value):
		armed = value
		for ship: Node3D in ships:
			ship.armed = value

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = fleet_seed
	flak = Flak.new()
	flak.target = focus
	add_child(flak)
	for i in FORMATION.size():
		var ship: Node3D = Airship.new()
		ship.build(FORMATION[i][1], fleet_seed * 100 + i)
		ship.speed = SPEED
		ship.target = focus
		ship.flak = flak
		ship.armed = armed
		add_child(ship)
		ships.append(ship)


## Put the convoy down with its flagship at a point, flying along a heading (radians, 0 = -Z).
func place(flagship_at: Vector3, heading: float) -> void:
	var turn := Basis(Vector3.UP, heading)
	for i in ships.size():
		var ship: Node3D = ships[i]
		var at: Vector3 = flagship_at + turn * (FORMATION[i][0] as Vector3)
		ship.heading = heading
		ship.cruise_y = at.y
		ship.position = at
		ship.rotation = Vector3(0, heading, 0)
		ship.reset_physics_interpolation()


func _physics_process(_delta: float) -> void:
	if focus == null or ships.is_empty():
		return
	var flagship: Node3D = ships[0]
	if flagship.position.distance_to(focus.position) < LOST_DISTANCE:
		return
	# Out of sight: bring the convoy across the glider's path, a long way ahead.
	var ahead: Vector3 = -focus.basis.z
	ahead.y = 0.0
	ahead = ahead.normalized() if ahead.length() > 0.01 else Vector3.FORWARD
	var glider_heading: float = atan2(-ahead.x, -ahead.z)
	var heading: float = glider_heading + _rng.randf_range(0.5, 1.1) * (1.0 if _rng.randf() < 0.5 else -1.0)
	var along := Vector3(-sin(heading), 0.0, -cos(heading))
	var meet: Vector3 = focus.position + ahead * 3200.0
	meet.y = clampf(focus.position.y + _rng.randf_range(-80.0, 120.0), floor_y, ceiling_y)
	place(meet - along * 1400.0, heading)


## Checks the glider against every ship. See Airship.hit().
func hit(world: Vector3, radius: float) -> Vector3:
	for ship: Node3D in ships:
		var push: Vector3 = ship.hit(world, radius)
		if push != Vector3.ZERO:
			return push
	return Vector3.ZERO
