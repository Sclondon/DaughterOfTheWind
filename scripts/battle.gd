extends Node3D
## The war in the sky: two fleets of airships fighting each other, and their fighters.
##
## The fleets sail the same wide circle side by side, a broadside apart, each ship's turrets
## hammering the ship opposite. The glider is fair game to both. Their fighters (squadron.gd)
## tangle above and between them. All the shells and explosions are one flak.gd.
##
## When the glider leaves the battle far behind, the whole thing is set down again nearer her.

const Fleet := preload("res://scripts/fleet.gd")
const Flak := preload("res://scripts/flak.gd")
const Squadron := preload("res://scripts/squadron.gd")

const RADIUS := 2600.0
## How far apart the two lines sail.
const GAP := 720.0
const LOST_DISTANCE := 9500.0

var focus: Node3D
## Optional: the land (coast.gd). With it the battle stays out over the sea.
var land: Node
## The middle of the circle the fleets sail round.
var centre := Vector3(0, 560, -2600)

var fleets: Array = []
var flak: Node3D
var squadron: Node3D
## False holds everyone's fire.
var armed := true:
	set(value):
		armed = value
		for fleet: Node3D in fleets:
			fleet.armed = value
		if squadron:
			squadron.armed = value


func _ready() -> void:
	flak = Flak.new()
	flak.target = focus
	add_child(flak)
	for side in 2:
		var fleet: Node3D = Fleet.new()
		fleet.focus = focus
		fleet.flak = flak
		fleet.faction = side
		fleet.fleet_seed = 77 + side * 40
		fleet.armed = armed
		add_child(fleet)
		fleets.append(fleet)
	fleets[0].set_foes(fleets[1].ships)
	fleets[1].set_foes(fleets[0].ships)
	squadron = Squadron.new()
	squadron.focus = focus
	squadron.fleets = fleets
	squadron.flak = flak
	squadron.land = land
	squadron.armed = armed
	add_child(squadron)
	place(centre, PI * 0.5)


## Set the battle down round a new middle, with the flagships at an angle round the circle.
func place(middle: Vector3, angle: float) -> void:
	centre = middle
	for side in 2:
		var fleet: Node3D = fleets[side]
		fleet.centre = centre + Vector3(0, side * 70.0, 0)
		fleet.radius = RADIUS + side * GAP
		fleet.turn = 1.0
		fleet.place_on_circle(angle)
	squadron.regroup()


## Checks a ball against every ship of both fleets. See Airship.hit().
func hit(world: Vector3, ball: float) -> Vector3:
	for fleet: Node3D in fleets:
		var push: Vector3 = fleet.hit(world, ball)
		if push != Vector3.ZERO:
			return push
	return Vector3.ZERO


func _physics_process(_delta: float) -> void:
	if focus == null:
		return
	var away := Vector2(focus.position.x - centre.x, focus.position.z - centre.z)
	if away.length() < LOST_DISTANCE:
		return
	if land:
		# Along the coast: keep the same distance off shore, and move level with her.
		place(Vector3(centre.x, centre.y, focus.position.z), PI if focus.basis.z.z > 0.0 else 0.0)
		return
	# Over the clouds: ahead of her, at about her height.
	var ahead: Vector3 = -focus.basis.z
	ahead.y = 0.0
	ahead = ahead.normalized() if ahead.length() > 0.01 else Vector3.FORWARD
	var middle: Vector3 = focus.position + ahead * (RADIUS + 1500.0)
	middle.y = clampf(focus.position.y, 450.0, 900.0)
	# Start the flagships on the near side of the circle.
	place(middle, atan2(-ahead.z, -ahead.x))
