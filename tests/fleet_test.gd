extends SceneTree
## Checks the airships: the fleet is there, and the glider cannot fly through a hull or a wing.
## Run: godot --headless --fixed-fps 60 --path . -s res://tests/fleet_test.gd

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
	main.use_pads = false
	main.show_hud = false
	root.add_child(main)
	await physics_frame
	var glider: Node3D = main.glider
	var fleet: Node3D = main.fleet
	main.input.manual = true
	glider.air = []
	# Hold fire for the collision checks; the guns get their own check at the end.
	fleet.armed = false
	glider.bumped.connect(func() -> void: bumps += 1)
	_check("a convoy is flying", fleet.ships.size() == 5, "%d ships" % fleet.ships.size())

	var flagship: Node3D = fleet.ships[0]
	var before: Vector3 = flagship.position
	for i in 60:
		await physics_frame
	_check("the ships cruise", flagship.position.distance_to(before) > 8.0, "moved %.1f m in a second" % flagship.position.distance_to(before))

	# Fly straight at the flagship's side, and at its wing from behind. Neither should let her through.
	# Each run: where to start from, in the ship's own space (x right, y up, z behind), and a turn
	# away from the ship's heading.
	var runs := [
		["hull", Vector3(160, 0, -20), PI * 0.5],
		["wing", Vector3(flagship.length * 0.15, 7, 14), 0.0],
	]
	for run: Array in runs:
		bumps = 0
		glider.reset(flagship.position + flagship.global_basis * (run[1] as Vector3), flagship.heading + float(run[2]))
		var deepest: float = 0.0
		for i in 420:
			await physics_frame
			deepest = maxf(deepest, flagship.hit(glider.position, 0.0).length())
		_check("she bounces off the %s" % run[0], bumps > 0 and deepest < 1.5, "%d bumps, deepest %.2f m inside" % [bumps, deepest])

	# Left far behind, the convoy comes round again ahead of her.
	glider.reset(Vector3(60000, 700, 60000))
	for i in 5:
		await physics_frame
	var gap: float = flagship.position.distance_to(glider.position)
	_check("the convoy finds her again", gap < 6000.0, "flagship %.0f m away" % gap)

	# The guns: fly straight and level past the flagship, above its deck, and it should open fire,
	# with the shells bursting close by.
	fleet.armed = true
	var flak: Node3D = fleet.flak
	glider.reset(flagship.position + flagship.global_basis * Vector3(180, 110, 420), flagship.heading)
	var top: Node3D = flagship._turrets[0][0]
	var aim: float = -1.0
	for i in 600:
		await physics_frame
		await process_frame
		# (She may be shot down and start again far away, so judge the aim as it goes.)
		aim = maxf(aim, (-top.global_basis.z).dot((glider.position - top.global_position).normalized()))
	_check("the turrets fire at her", flak.shots_fired > 10 and flak.bursts + flak.hits > 5 and flak.closest < 30.0,
			"%d shots, %d bursts, %d hits, closest %.1f m, health %d" % [flak.shots_fired, flak.bursts, flak.hits, flak.closest, glider.health])
	_check("the turrets track her", aim > 0.9, "aim %.2f" % aim)

	print("fleet_test: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
