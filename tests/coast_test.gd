extends SceneTree
## Checks the coast level: the land is there and is solid, the cliffs make lift, things were placed.
## Run: godot --headless --fixed-fps 60 --path . -s res://tests/coast_test.gd

const Main := preload("res://scenes/main.tscn")

var passed := 0
var failed := 0
var bumps := 0


func _initialize() -> void:
	_run()


func _check(what: String, ok: bool, detail: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("%s  %s  (%s)" % ["PASS" if ok else "FAIL", what, detail])


func _run() -> void:
	var main: Node3D = Main.instantiate()
	main.level = "coast"
	main.use_pads = false
	main.show_hud = false
	root.add_child(main)
	await physics_frame
	var coast: Node3D = main.coast
	var glider: Node3D = main.glider
	main.input.manual = true
	glider.bumped.connect(func() -> void: bumps += 1)

	_check("there is land in the middle and sea far out", coast.height_at(0, 0) > 150.0 and coast.height_at(9000, 0) < 0.0,
			"middle %.0f m, far out %.0f m" % [coast.height_at(0, 0), coast.height_at(9000, 0)])
	_check("the island is furnished", coast.windmills >= 12 and coast.houses >= 80 and coast.spires >= 20,
			"%d windmills, %d houses, %d spires" % [coast.windmills, coast.houses, coast.spires])

	# Walk in from the south until the cliff: the ground should jump up steeply there.
	var edge: float = 0.0
	for z in range(4200, 0, -10):
		if coast.height_at(0, z) > 60.0:
			edge = float(z)
			break
	var foot: float = coast.height_at(0, edge + 120.0)
	_check("the south coast is a cliff", edge > 0.0 and foot <= 0.0, "cliff top at z=%.0f, %.0f m at 120 m out" % [edge, foot])
	var lift: float = coast.wind_at(Vector3(0, 220, edge + 20.0)).y
	_check("the sea wind rises up the cliff", lift > 2.5, "%.1f m/s" % lift)
	var start: Vector3 = coast.start_position()
	_check("she starts in clear air over the sea", coast.hit(start, 3.0) == Vector3.ZERO and coast.height_at(start.x, start.z) < 0.0, str(start))

	# Fly level straight at the cliff face, and dive at the sea. She must stay out of both.
	glider.air = []
	glider.reset(Vector3(0, 70, edge + 300.0))
	var deepest: float = 0.0
	for i in 1500:
		await physics_frame
		deepest = maxf(deepest, maxf(coast.height_at(glider.position.x, glider.position.z), 0.0) - glider.position.y)
	_check("she cannot fly through the cliff or the sea", bumps > 0 and deepest < 1.0, "%d bumps, deepest %.2f m under" % [bumps, deepest])

	print("coast_test: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
