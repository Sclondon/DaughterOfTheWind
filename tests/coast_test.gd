extends SceneTree
## Checks the coast level: the cliffs and the cities built into them, the trenches and their
## bridges, the valley and its castle, the painted backdrop, that the land goes on north and
## south, that it is solid, and that the cliffs make lift.
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
	var nearest_ship: float = INF
	for side: Node3D in main.battle.fleets:
		for ship: Node3D in side.ships:
			nearest_ship = minf(nearest_ship, coast.inland(ship.position.x, ship.position.z))
	var from_mouth: float = main.battle.centre.distance_to(Vector3(coast.shore_x(0.0), main.battle.centre.y, 0.0))
	_check("two fleets fight at the mouth of the valley", main.battle.fleets.size() == 2 and nearest_ship < -40.0 and from_mouth < 2500.0,
			"the battle's middle is %.0f m off the beach; nearest ship %.0f m off shore" % [from_mouth, -nearest_ship])
	main.battle.armed = false
	glider.bumped.connect(func() -> void: bumps += 1)

	# Away from the valley: sea to the west, and the cliffs straight out of it to the east.
	var z: float = 3000.0
	var shore: float = coast.shore_x(z)
	_check("sea to the west, land to the east", coast.height_at(shore - 3000.0, z) < 0.0 and coast.height_at(shore + 3000.0, z) > 300.0,
			"%.0f m out at sea, %.0f m inland" % [coast.height_at(shore - 3000.0, z), coast.height_at(shore + 3000.0, z)])
	_check("the cliffs tower", coast.height_at(shore + 900.0, z) > 480.0 and coast.height_at(shore + 60.0, z) > 80.0,
			"%.0f m at the top, %.0f m just 60 m in from the water" % [coast.height_at(shore + 900.0, z), coast.height_at(shore + 60.0, z)])
	var lift: float = coast.wind_at(Vector3(shore + 40.0, 260.0, z)).y
	_check("the sea wind rises up the cliff", lift > 2.5, "%.1f m/s" % lift)

	# The valley: a beach at the water, a gentle climb, and the castle standing in it.
	var vs: float = coast.shore_x(coast.VALLEY_Z)
	var beach: float = coast.height_at(vs + 120.0, coast.valley_mid(vs + 120.0))
	var floor_600: float = coast.height_at(vs + 600.0, coast.valley_mid(vs + 600.0))
	_check("the valley runs gently down to a beach", beach > 0.0 and beach < 9.0 and floor_600 < 75.0,
			"%.1f m at the beach, %.0f m at 600 m in (the cliffs are %.0f m there)" % [beach, floor_600, coast.height_at(shore + 600.0, z)])
	_check("the castle stands in the valley", coast.valley(coast.castle.x, coast.castle.z) > 0.9 and coast.hit(coast.castle + Vector3(20, 120, 0), 2.0) != Vector3.ZERO,
			"at %s" % coast.castle)

	var here: Dictionary = coast.stats()
	_check("cities are built into the cliffs", here["city_houses"] >= 600 and here["towers"] >= 10 and here["stairs"] >= 40 and here["bridges"] >= 4,
			"%d houses, %d towers, %d flights of stairs, %d viaducts and bridges" % [here["city_houses"], here["towers"], here["stairs"], here["bridges"]])
	_check("the cliffs are broken rock", here["outcrops"] >= 400 and here["rock_towers"] >= 15,
			"%d outcrops, %d rock towers" % [here["outcrops"], here["rock_towers"]])
	# Along a line half way up the cliffs, the ground should rise and fall with the buttresses.
	var lowest: float = INF
	var highest: float = -INF
	for i in 60:
		var zz: float = 3000.0 + i * 12.0
		var hh: float = coast.height_at(coast.shore_x(zz) + 350.0, zz)
		lowest = minf(lowest, hh)
		highest = maxf(highest, hh)
	_check("the cliff face is not smooth", highest - lowest > 60.0, "over 700 m of it, 350 m in, the ground runs from %.0f to %.0f m" % [lowest, highest])

	# The nearest trench: a slot of sea between sheer walls, with a bridge over it to fly under.
	var k: int = 1
	var tx: float = coast.shore_x(coast.trench_z(k)) + 190.0 + 70.0 * sin(float(k) * 3.3)
	var tz: float = coast.trench_mid(k, tx)
	var half: float = coast.trench_half(k, coast.inland(tx, tz))
	_check("trenches cut the cliffs", coast.height_at(tx, tz) < 0.0 and coast.height_at(tx, tz - half * 1.3) > 120.0 and coast.height_at(tx, tz + half * 1.3) > 120.0
			and half * 2.0 < coast.VALLEY_HALF and coast.height_at(tx + 1500.0, coast.trench_mid(k, tx + 1500.0)) > 150.0,
			"%.0f m wide at z %.0f: %.0f m in the middle, %.0f and %.0f m either side, %.0f m on its floor 1.5 km further in" % [half * 2.0, tz,
			coast.height_at(tx, tz), coast.height_at(tx, tz - half * 1.3), coast.height_at(tx, tz + half * 1.3), coast.height_at(tx + 1500.0, coast.trench_mid(k, tx + 1500.0))])
	var ways_under := 0
	var deck: float = 0.0
	for i in 40:
		var zz: float = tz - half + half * 2.0 * float(i) / 39.0
		if coast.hit(Vector3(tx, 45.0, zz), 5.0) == Vector3.ZERO:
			ways_under += 1
		for y in range(60, 270, 6):
			if coast.hit(Vector3(tx, float(y), zz), 3.0) != Vector3.ZERO:
				deck = maxf(deck, float(y))
	_check("a bridge crosses it, with room to fly under", deck > 90.0 and ways_under > 12, "solid up to %.0f m; clear at 45 m at %d of 40 places across" % [deck, ways_under])

	var flats: Vector4 = coast._backdrop_mat.get_shader_parameter("planes")
	_check("a painted backdrop stands inland", coast._backdrop.visible and flats.x > coast.shore_x(0.0) + 6000.0 and flats.w > flats.z and flats.z > flats.y and flats.y > flats.x,
			"flats at x = %.0f, %.0f, %.0f, %.0f" % [flats.x, flats.y, flats.z, flats.w])
	_check("the sea is a maze of spires and arches", here["spires"] >= 40 and here["arches"] >= 6, "%d spires, %d arches" % [here["spires"], here["arches"]])
	_check("giant trees stand in the valley and on the cliffs", here["great_trees"] >= 12, "%d great trees, besides the five by the castle" % here["great_trees"])
	var up_valley: float = coast.shore_x(0.0) + 2400.0
	var bumpy: float = 0.0
	for i in 20:
		var zz: float = coast.valley_mid(up_valley) - 200.0 + i * 20.0
		bumpy = maxf(bumpy, absf(coast.height_at(up_valley, zz) - coast.height_at(up_valley, zz + 20.0)))
	_check("the valley floor is not smooth", bumpy > 1.5, "steepest 20 m step across it: %.1f m" % bumpy)
	var start: Vector3 = coast.start_position()
	_check("she starts in clear air over the sea", coast.hit(start, 3.0) == Vector3.ZERO and coast.height_at(start.x, start.z) < 0.0, str(start))

	# Fly level straight at the cliff face. She must stay out of it, and out of the sea after.
	glider.air = []
	glider.reset(Vector3(shore - 300.0, 70.0, z), -PI * 0.5)
	var deepest: float = 0.0
	for i in 1500:
		await physics_frame
		deepest = maxf(deepest, maxf(coast.surface_at(glider.position.x, glider.position.z), 0.0) - glider.position.y)
	_check("she cannot fly through the cliff or the sea", bumps > 0 and deepest < 1.0, "%d bumps, deepest %.2f m under" % [bumps, deepest])

	# A long way north the coast is still there, built around her as she arrives.
	glider.set_physics_process(false)
	var far_z: float = -60000.0
	glider.position = Vector3(coast.shore_x(far_z) + 200.0, 900.0, far_z)
	for i in 240:
		await process_frame
	var there: Dictionary = coast.stats()
	flats = coast._backdrop_mat.get_shader_parameter("planes")
	_check("the coast goes on for ever", coast.height_at(coast.shore_x(far_z) + 900.0, far_z) > 480.0 and there["chunks"] > 100 and there["city_houses"] > 100,
			"60 km north: %s" % str(there))
	# Fly far inland and the backdrop backs away.
	glider.position = Vector3(9000.0, 1500.0, far_z)
	for i in 5:
		await process_frame
	flats = coast._backdrop_mat.get_shader_parameter("planes")
	_check("the backdrop keeps its distance", flats.x > glider.position.x + 6000.0, "the nearest flat is %.0f m ahead of her" % (flats.x - glider.position.x))

	print("coast_test: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
