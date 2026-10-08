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
	var battle: Node3D = main.battle
	main.input.manual = true
	glider.air = []
	# Hold fire for the collision checks; the guns get their own check at the end.
	battle.armed = false
	glider.bumped.connect(func() -> void: bumps += 1)
	_check("two fleets are flying", battle.fleets.size() == 2 and fleet.ships.size() == 5 and battle.fleets[1].ships.size() == 5,
			"%d and %d ships" % [fleet.ships.size(), battle.fleets[1].ships.size()])
	_check("they are painted as two sides", fleet.ships[0]._metal.get_shader_parameter("base_color") != battle.fleets[1].ships[0]._metal.get_shader_parameter("base_color"), "")
	_check("each side has fighters up", battle.squadron.fighters.size() == 8, "%d fighters" % battle.squadron.fighters.size())

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

	# The two sides shoot at each other, and their fighters fight: hold her well out of it and watch.
	battle.armed = true
	glider.reset(flagship.position + Vector3(0, 2500, 0))
	glider.set_physics_process(false)
	var flak: Node3D = battle.flak
	for i in 2400:
		await process_frame
	_check("the fleets fire on each other", flak.shots_fired > 40 and flak.bursts > 30, "%d shots, %d bursts with her out of range" % [flak.shots_fired, flak.bursts])
	_check("fighters shoot fighters down", battle.squadron.losses > 0, "%d shot down in 40 s" % battle.squadron.losses)
	var strayed: float = 0.0
	for fighter in battle.squadron.fighters:
		strayed = maxf(strayed, fighter.node.position.distance_to(battle.centre))
	_check("the fighters stay with the battle", strayed < 9000.0, "furthest %.0f m from the middle" % strayed)
	glider.set_physics_process(true)
	battle.armed = false

	# Left far behind, the battle is set down again near her.
	glider.reset(Vector3(60000, 700, 60000))
	for i in 5:
		await physics_frame
	var gap: float = flagship.position.distance_to(glider.position)
	_check("the battle finds her again", gap < 9000.0, "flagship %.0f m away" % gap)

	# The guns: fly straight and level past the flagship, above its deck, and it should open fire,
	# with the shells bursting close by.
	battle.armed = true
	flak.shots_fired = 0
	flak.bursts = 0
	flak.hits = 0
	flak.closest = INF
	battle.squadron.armed = false
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
