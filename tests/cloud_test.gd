extends SceneTree
## Checks the cloud manager: cells stream in and out as the focus moves, the same place always
## grows the same clouds, and the questions about the air give sensible answers.
## Run: godot --headless --fixed-fps 60 --path . -s res://tests/cloud_test.gd

const Main := preload("res://scenes/main.tscn")

var passed := 0
var failed := 0


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
	main.use_fleet = false
	main.use_pads = false
	main.show_hud = false
	root.add_child(main)
	await physics_frame
	var clouds: Node3D = main.clouds
	var glider: Node3D = main.glider
	main.input.manual = true
	glider.set_physics_process(false)
	# Hold the sky still so positions can be compared.
	clouds.wind = Vector3.ZERO

	var start: Dictionary = clouds.stats()
	_check("the sky is full at the start", start["clouds"] > 30 and start["puffs"] > 600 and start["queued"] == 0,
			str(start))

	# Inside a puff is cloud; high above everything is clear.
	var some: Array = clouds.all_clouds()
	var cloud = some[some.size() / 2]
	var puff: Vector3 = Vector3(cloud.puffs[0], cloud.puffs[1], cloud.puffs[2]) + clouds.drift
	_check("inside a puff reads as cloud", clouds.density_at(puff) > 0.9, "%.2f" % clouds.density_at(puff))
	_check("high above is clear", clouds.density_at(Vector3(0, 5000, 0)) == 0.0, "%.2f" % clouds.density_at(Vector3(0, 5000, 0)))
	_check("deep in the cloud sea is cloud", clouds.density_at(Vector3(0, -50, 0)) > 0.9, "%.2f" % clouds.density_at(Vector3(0, -50, 0)))

	# Air rises under a cumulus and is still out in the open.
	var thermal = null
	for c in some:
		if c.thermal > 0.0:
			thermal = c
			break
	var under: Vector3 = thermal.foot + clouds.drift
	under.y = 250.0
	_check("air rises under a cloud", clouds.wind_at(under).y > 3.0, "%.1f m/s" % clouds.wind_at(under).y)
	_check("the cloud sea pushes up", clouds.wind_at(Vector3(40000, -30, 0)).y > 15.0, "%.1f m/s" % clouds.wind_at(Vector3(40000, -30, 0)).y)

	# Remember one cloud, fly far away, then come back: it should have been freed and regrown the same.
	var remembered: Vector3 = cloud.center
	var remembered_puffs: int = cloud.puffs.size()
	glider.position = Vector3(30000, 600, 12000)
	for i in 400:
		await process_frame
	var away: Dictionary = clouds.stats()
	var still_there := false
	for c in clouds.all_clouds():
		if c.center.distance_to(remembered) < 1.0:
			still_there = true
	_check("cells stream in around the new place", away["queued"] == 0 and away["clouds"] > 10, str(away))
	_check("old cells are let go", not still_there and away["cells"] <= start["cells"] + 60, "cells %d -> %d" % [start["cells"], away["cells"]])

	glider.position = Vector3(0, 600, 0)
	for i in 400:
		await process_frame
	var regrown := false
	for c in clouds.all_clouds():
		if c.center.distance_to(remembered) < 0.01 and c.puffs.size() == remembered_puffs:
			regrown = true
	_check("the same place grows the same cloud", regrown, "looked for %s" % remembered)

	# Heavier weather means more cloud.
	clouds.set_weather(0)
	var clear: int = clouds.stats()["puffs"]
	clouds.set_weather(2)
	var heavy: int = clouds.stats()["puffs"]
	_check("weather changes the cover", heavy > clear * 1.5, "clear %d puffs, heavy %d" % [clear, heavy])

	print("cloud_test: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
