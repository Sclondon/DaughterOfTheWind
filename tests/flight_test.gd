extends SceneTree
## Flies the glider by script and checks that the flight model behaves like a glider.
## Run: godot --headless --fixed-fps 60 --path . -s res://tests/flight_test.gd

const Main := preload("res://scenes/main.tscn")

var main: Node3D
var glider: Node3D
var input: Node
var passed := 0
var failed := 0


func _initialize() -> void:
	_run()


func _fly(seconds: float, stick: Vector2, boost: bool = false) -> void:
	input.stick = stick
	input.boost = boost
	for i in int(seconds * 60.0):
		await physics_frame


func _check(what: String, ok: bool, detail: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("%s  %s  (%s)" % ["PASS" if ok else "FAIL", what, detail])


func _heading() -> float:
	var f: Vector3 = -glider.basis.z
	return atan2(f.x, -f.z)


func _run() -> void:
	main = Main.instantiate()
	main.use_fleet = false
	main.use_pads = false
	main.show_hud = false
	root.add_child(main)
	await physics_frame
	glider = main.glider
	input = main.input
	input.manual = true

	# 1. Hands off in still air: it should settle into a steady, shallow glide.
	glider.clouds = null
	glider.reset(Vector3(0, 3000, 0))
	await _fly(30.0, Vector2.ZERO)
	var y0: float = glider.position.y
	var speeds: Array = []
	for i in 10:
		await _fly(1.0, Vector2.ZERO)
		speeds.append(glider.airspeed)
	var sink: float = (y0 - glider.position.y) / 10.0
	var wobble: float = (speeds.max() as float) - (speeds.min() as float)
	_check("steady glide", glider.airspeed > 24.0 and glider.airspeed < 38.0 and sink > 0.8 and sink < 4.5 and wobble < 2.0,
			"speed %.1f m/s, sink %.2f m/s, wobble %.2f" % [glider.airspeed, sink, wobble])

	# 2. Pulling up trades speed for height.
	var y1: float = glider.position.y
	var v1: float = glider.airspeed
	await _fly(2.5, Vector2(0, 1))
	_check("pull up climbs", glider.position.y > y1 + 8.0 and glider.airspeed < v1 - 3.0,
			"rose %.1f m, speed %.1f -> %.1f" % [glider.position.y - y1, v1, glider.airspeed])

	# 3. Holding the stick back must not end in a tumble: it mushes along slowly, nose still forward.
	await _fly(12.0, Vector2(0, 1))
	_check("held pull stays flyable", glider.basis.y.y > 0.3 and glider.airspeed > 10.0,
			"up.y %.2f, speed %.1f" % [glider.basis.y.y, glider.airspeed])

	# 4. Diving buys speed.
	await _fly(8.0, Vector2.ZERO)
	var v2: float = glider.airspeed
	await _fly(4.0, Vector2(0, -1))
	_check("dive gains speed", glider.airspeed > v2 + 12.0, "speed %.1f -> %.1f" % [v2, glider.airspeed])

	# 5. Banking turns it, without falling out of the sky.
	await _fly(12.0, Vector2.ZERO)
	var h0: float = _heading()
	var y2: float = glider.position.y
	await _fly(3.0, Vector2(1, 0))
	var turned: float = wrapf(_heading() - h0, -PI, PI)
	var lost: float = y2 - glider.position.y
	_check("bank right turns right", turned > 1.0 and absf(lost) < 30.0,
			"turned %.0f deg, lost %.1f m" % [rad_to_deg(turned), lost])
	await _fly(4.0, Vector2.ZERO)
	_check("levels out hands off", absf(glider.basis.x.y) < 0.08, "right.y %.3f" % glider.basis.x.y)

	# 6. The jet pushes.
	await _fly(8.0, Vector2.ZERO)
	var v3: float = glider.airspeed
	await _fly(3.0, Vector2.ZERO, true)
	_check("boost adds speed and burns fuel", glider.airspeed > v3 + 8.0 and glider.burn < 0.5,
			"speed %.1f -> %.1f, fuel %.2f" % [v3, glider.airspeed, glider.burn])

	# 7. With the real air back, the wind lifts a glider that has sunk into the cloud sea.
	glider.clouds = main.clouds
	glider.reset(Vector3(0, -40, 0))
	await _fly(20.0, Vector2.ZERO)
	_check("the cloud sea carries her back up", glider.position.y > 10.0, "height %.1f m" % glider.position.y)

	print("flight_test: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
