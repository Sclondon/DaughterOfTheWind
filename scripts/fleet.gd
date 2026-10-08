extends Node3D
## One side's airships: a line of giant ships sailing round a wide circle. battle.gd makes two of
## these, puts them on the same circle side by side, and points each one's guns at the other.

const Airship := preload("res://scripts/airship.gd")

## Where each ship flies relative to the flagship (x right, y up, z behind), and how long it is.
const FORMATION := [
	[Vector3(0, 0, 0), 320.0],
	[Vector3(-90, -40, 520), 210.0],
	[Vector3(110, 35, 980), 230.0],
	[Vector3(-70, 25, 1420), 170.0],
	[Vector3(60, -45, 1830), 180.0],
]
const SPEED := 13.0

var focus: Node3D
var flak: Node3D
## 0 or 1: which side this is. It decides the ships' paint.
var faction := 0
var fleet_seed := 77
var ships: Array = []
## The circle the fleet sails: its middle, its radius, and which way round (1 or -1).
var centre := Vector3.ZERO
var radius := 2600.0
var turn := 1.0
## False holds fire (the guns still track).
var armed := true:
	set(value):
		armed = value
		for ship: Node3D in ships:
			ship.armed = value


func _ready() -> void:
	for i in FORMATION.size():
		var ship: Node3D = Airship.new()
		ship.build(FORMATION[i][1], fleet_seed * 100 + i, faction)
		ship.speed = SPEED
		ship.target = focus
		ship.flak = flak
		ship.armed = armed
		add_child(ship)
		ships.append(ship)


## Tell every ship which ships it is fighting.
func set_foes(foes: Array) -> void:
	for ship: Node3D in ships:
		ship.foes = foes


## Put the fleet on its circle with the flagship at an angle round it (radians).
func place_on_circle(angle: float) -> void:
	var out := Vector3(cos(angle), 0.0, sin(angle))
	# Sailing along the circle: a quarter turn on from "outward".
	var along := Vector3(-sin(angle), 0.0, cos(angle)) * turn
	place(centre + out * radius, atan2(-along.x, -along.z))


## Put the fleet down with its flagship at a point, flying along a heading (radians, 0 = -Z).
func place(flagship_at: Vector3, heading: float) -> void:
	var facing := Basis(Vector3.UP, heading)
	for i in ships.size():
		var ship: Node3D = ships[i]
		var at: Vector3 = flagship_at + facing * (FORMATION[i][0] as Vector3)
		ship.heading = heading
		ship.cruise_y = at.y
		ship.position = at
		ship.rotation = Vector3(0, heading, 0)
		ship.reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	# Every ship turns at the rate that carries it round the circle.
	# (Heading 0 is -Z and a positive heading turns left, so going round clockwise seen from
	# above, which is `turn` = 1 here, means the heading falls.)
	for ship: Node3D in ships:
		ship.heading -= turn * SPEED / radius * delta


## Checks a ball against every ship. See Airship.hit().
func hit(world: Vector3, ball: float) -> Vector3:
	for ship: Node3D in ships:
		var push: Vector3 = ship.hit(world, ball)
		if push != Vector3.ZERO:
			return push
	return Vector3.ZERO
