extends SceneTree
## Checks the cloud manager: cells stream in and out as the focus moves, the same place always
## grows the same clouds, the questions about the air give sensible answers, the towers carry
## thunderheads, the glider and the airships stir the puffs, tufts break off, and the cirrus is up.
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

	# A tower spreads out at the top into a thunderhead: wider up there than at its foot.
	var widest := 0.0
	for c in some:
		if c.puffs[3] < 100.0:
			continue
		var top := 0.0
		var bottom := 0.0
		for i in range(0, c.puffs.size(), 4):
			var out: float = Vector2(c.puffs[i] - c.foot.x, c.puffs[i + 2] - c.foot.z).length()
			if c.puffs[i + 1] > lerpf(c.foot.y, c.top_y, 0.75):
				top = maxf(top, out)
			elif c.puffs[i + 1] < lerpf(c.foot.y, c.top_y, 0.5):
				bottom = maxf(bottom, out)
		widest = maxf(widest, top / maxf(bottom, 1.0))
	_check("the towers are topped by thunderheads", widest > 1.3, "the top reaches %.1f times as far out as the foot" % widest)
	_check("clouds have tufts round their edges", start["tufts"] > 100 and start["tufts"] < start["puffs"], "%d tufts among %d puffs" % [start["tufts"], start["puffs"]])

	# The cirrus lies far above everything, over the glider.
	var cirrus: MeshInstance3D = clouds._cirrus
	var highest := 0.0
	for c in some:
		highest = maxf(highest, c.top_y)
	_check("cirrus lies above every other cloud", cirrus.visible and cirrus.global_position.y > highest + 500.0
			and Vector2(cirrus.global_position.x - glider.position.x, cirrus.global_position.z - glider.position.z).length() < 1.0,
			"at %.0f m, the highest cloud top %.0f m" % [cirrus.global_position.y, highest])

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

	# Fly through a cloud: its puffs should be knocked out of place, and settle back afterwards.
	var target = null
	for c in clouds.all_clouds():
		if c.puffs.size() >= 40:
			target = c
			break
	var through: Vector3 = Vector3(target.puffs[0], target.puffs[1], target.puffs[2]) + clouds.drift
	glider.velocity = Vector3(0, 0, -40)
	for i in 90:
		glider.position = through + Vector3(0, 0, 60.0 - i * 1.4)
		await process_frame
	var knocked: int = 0
	var furthest: float = 0.0
	for cell in clouds._unsettled:
		for i in cell.stirred:
			knocked += 1
			furthest = maxf(furthest, (cell.stirred[i][0] as Vector3).length())
	_check("flying through a cloud swooshes its puffs aside", knocked >= 2 and furthest > 8.0, "%d puffs moved, the furthest %.0f m" % [knocked, furthest])

	# Brush past a tuft: it should break off, blow away and thin to nothing.
	var tuft_cell = null
	var tuft_i := -1
	for cell in clouds._cells[0].values():
		if cell.node and cell.stirred.is_empty() and cell.tuft.count(1) > 0:
			tuft_cell = cell
			tuft_i = cell.tuft.find(1)
			break
	var tuft_at: Vector3 = (tuft_cell.base[tuft_i] as Transform3D).origin + clouds.drift
	for i in 30:
		glider.position = tuft_at + Vector3(4, 3, 20.0 - i * 1.4)
		await process_frame
	glider.position = Vector3(0, 5000, 0)
	var broke: bool = tuft_cell.stirred.has(tuft_i) and (tuft_cell.stirred[tuft_i][3] as float) > 0.0
	for i in 120:
		await process_frame
	var blown: float = (tuft_cell.stirred[tuft_i][0] as Vector3).length() if broke else 0.0
	for i in int(clouds.TUFT_LIFE * 60.0):
		await process_frame
	# (Headless there is no MultiMesh to read back, so ask the manager's own record.)
	var gone: bool = broke and (tuft_cell.stirred[tuft_i][3] as float) > clouds.TUFT_LIFE
	_check("a tuft breaks off and blows away", broke and blown > 10.0 and gone, "carried %.0f m in two seconds, gone after %.0f" % [blown, clouds.TUFT_LIFE])

	# An airship ploughs through a tower while the glider is off stirring nothing: the puffs in
	# its way are shouldered aside and the tunnel stays open after it has gone.
	var tower = null
	for c in clouds.all_clouds():
		if c.puffs[3] > 100.0:
			tower = c
			break
	var hull := Node3D.new()
	root.add_child(hull)
	clouds.add_stirrer(hull, 30.0, 240.0)
	var decoy := Node3D.new()
	root.add_child(decoy)
	clouds.add_stirrer(decoy, 20.0, 150.0)
	var line: Vector3 = Vector3(tower.puffs[0], tower.puffs[1], tower.puffs[2]) + clouds.drift
	var in_the_way := 0
	var cell_of_tower = null
	for cell in clouds._cells[1].values():
		if cell.clouds.has(tower):
			cell_of_tower = cell
	for i in cell_of_tower.base.size():
		var o: Vector3 = (cell_of_tower.base[i] as Transform3D).origin + clouds.drift - line
		if cell_of_tower.tuft[i] == 0 and Vector2(o.x, o.y).length() < 30.0 + cell_of_tower.radii[i] * 0.5:
			in_the_way += 1
	for i in 60 * 40:
		hull.position = line + Vector3(0, 0, 500.0 - i * 0.25)
		decoy.position = Vector3(20000, 600, i * 0.25)
		await process_frame
	hull.position = Vector3(0, 9000, 0)
	for i in 300:
		await process_frame
	var cleared := 0
	var held := 0
	for i in cell_of_tower.base.size():
		var entry = cell_of_tower.stirred.get(i)
		if entry == null or cell_of_tower.tuft[i] == 1:
			continue
		if (entry[2] as float) > 0.0:
			held += 1
		var o: Vector3 = (cell_of_tower.base[i] as Transform3D).origin + (entry[0] as Vector3) + clouds.drift - line
		var was: Vector3 = (cell_of_tower.base[i] as Transform3D).origin + clouds.drift - line
		if Vector2(o.x, o.y).length() > Vector2(was.x, was.y).length() + 15.0:
			cleared += 1
	_check("an airship punches a hole that stays open behind it", clouds.stirrers.size() == 3 and in_the_way >= 2 and cleared >= 2 and held >= cleared,
			"%d stirrers; %d puffs lay across its path, %d still pushed 15 m or more clear five seconds on" % [clouds.stirrers.size(), in_the_way, cleared])
	hull.free()
	decoy.free()
	await process_frame
	_check("stirrers that are gone are forgotten", clouds.stirrers.size() == 1, "%d left" % clouds.stirrers.size())

	glider.position = Vector3(0, 5000, 0)
	for i in 9000:
		await process_frame
		if clouds._unsettled.is_empty():
			break
	_check("and they drift back into place", clouds._unsettled.is_empty(), "%d cells still unsettled" % clouds._unsettled.size())
	glider.position = Vector3(0, 600, 0)
	for i in 30:
		await process_frame

	# Heavier weather means more cloud.
	clouds.set_weather(0)
	var clear: int = clouds.stats()["puffs"]
	clouds.set_weather(2)
	var heavy: int = clouds.stats()["puffs"]
	_check("weather changes the cover", heavy > clear * 1.5, "clear %d puffs, heavy %d" % [clear, heavy])
	var streaked: float = clouds._cirrus_mat.get_shader_parameter("cover")
	clouds.set_weather(0)
	_check("and the cirrus with it", streaked > (clouds._cirrus_mat.get_shader_parameter("cover") as float) + 0.2,
			"heavy %.1f, clear %.1f" % [streaked, clouds._cirrus_mat.get_shader_parameter("cover")])

	print("cloud_test: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
