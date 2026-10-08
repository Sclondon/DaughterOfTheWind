extends SceneTree
## Takes a set of screenshots for checking the look. Needs a window (no --headless).
## Run: godot --fixed-fps 60 --path . -s res://tests/shots.gd -- <output folder>

const Main := preload("res://scenes/main.tscn")

var main: Node3D
var out_dir := "user://shots"
var free_cam: Camera3D


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run()


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _save(shot: String) -> void:
	await _wait(3)
	var image: Image = root.get_texture().get_image()
	image.save_png(out_dir.path_join(shot + ".png"))
	print("saved ", shot)


func _coast_shots() -> void:
	var glider: Node3D = main.glider
	var coast: Node3D = main.coast
	var c: Vector3 = coast.castle
	# Along the cliffs, the terraces close up, the valley from the sea, the castle, and from high up.
	var views := [
		["20_cliffs", Vector3(-700, 300, 3600), 0.25],
		["21_terraces", Vector3(-150, 420, 2600), -0.5],
		["22_valley", Vector3(-1500, 260, 150), -PI * 0.5],
		["23_castle", Vector3(c.x - 900, c.y + 230, c.z + 250), -PI * 0.5 + 0.25],
		["24_high", Vector3(-3500, 1900, 2500), -1.1],
		["19_spires", Vector3(-1500, 190, 3400), 0.15],
		["18_sun", Vector3(-2500, 400, -3000), 0.65],
		["26_top", Vector3(1800, 1000, -2500), -1.0],
	]
	for view: Array in views:
		glider.reset(view[1], view[2])
		main.cam.snap()
		main.clouds.prewarm()
		coast.prewarm()
		await _wait(50)
		await _save(view[0])
	glider.reset(c + Vector3(-600, 300, 300), -PI * 0.5)
	coast.prewarm()
	_view(Vector3(c.x - 330, c.y + 150, c.z + 300), c + Vector3(0, 70, 0), 55.0)
	await _save("25_castle_close")
	# The convoy opening fire: fly past the flagship above its deck.
	var flagship: Node3D = main.fleet.ships[0]
	main.cam.make_current()
	# Between the two lines of ships.
	glider.reset(flagship.position + flagship.global_basis * Vector3(-330, 60, 700), flagship.heading)
	main.cam.snap()
	for i in 12:
		await _wait(22)
		glider.health = 5
	await _save("27_flak")
	await _wait(14)
	await _save("28_flak")
	# An explosion close up, early and late.
	main.battle.armed = false
	# A fighter, close up.
	var fighter: Node3D = main.battle.squadron.fighters[0].node
	main.battle.squadron.set_process(false)
	fighter.transform = Transform3D(Basis(Vector3.UP, 0.6), Vector3(-3000, 900, 9000))
	_view(fighter.position + Vector3(7, 4, -9), fighter.position, 50.0)
	await _save("31_fighter")
	_view(fighter.position + Vector3(-2, 11, 4), fighter.position, 50.0)
	await _save("32_fighter_top")
	main.cam.make_current()
	glider.reset(Vector3(-3000, 600, 6000), -PI * 0.5)
	main.cam.snap()
	await _wait(30)
	main.fleet.flak.burst(glider.position - glider.basis.z * 34.0 + Vector3(9, 5, 0))
	await _wait(9)
	await _save("29_burst_early")
	main.fleet.flak.burst(glider.position - glider.basis.z * 30.0 + Vector3(-12, 2, 0))
	await _wait(22)
	await _save("30_burst_late")


## Look at a point from an offset, with a separate camera.
func _view(from: Vector3, at: Vector3, fov: float = 60.0) -> void:
	free_cam.fov = fov
	free_cam.global_transform = Transform3D(Basis.looking_at(at - from, Vector3.UP), from)
	free_cam.make_current()


func _run() -> void:
	main = Main.instantiate()
	main.use_pads = false
	# "-- <folder> coast" shoots the coast level instead.
	if OS.get_cmdline_user_args().size() > 1:
		main.level = OS.get_cmdline_user_args()[1]
	if OS.get_cmdline_user_args().size() > 2:
		main.rider = OS.get_cmdline_user_args()[2]
	root.add_child(main)
	await _wait(2)
	var glider: Node3D = main.glider
	var input: Node = main.input
	input.manual = true
	free_cam = Camera3D.new()
	free_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	free_cam.near = 0.3
	free_cam.far = 16000.0
	main.add_child(free_cam)

	await _wait(40)
	await _save("01_start")

	# Close on the glider, from three sides, frozen in place.
	glider.set_physics_process(false)
	var g: Vector3 = glider.position
	_view(g + Vector3(5.5, 2.2, -6.5), g, 50.0)
	await _save("02_glider_front")
	_view(g + Vector3(-6.0, 3.5, 6.0), g, 50.0)
	await _save("03_glider_back")
	_view(g + Vector3(0.5, 9.0, 1.0), g, 50.0)
	await _save("04_glider_top")
	_view(g + Vector3(7.0, -1.5, 0.5), g, 50.0)
	await _save("05_glider_side")

	# A banked, boosting turn through the chase camera.
	glider.set_physics_process(true)
	main.cam.make_current()
	input.stick = Vector2(1.0, 0.3)
	input.boost = true
	await _wait(100)
	await _save("06_turn")
	input.stick = Vector2.ZERO
	input.boost = false

	if main.level == "coast":
		await _coast_shots()
		quit()
		return

	# The fleet.
	var flagship: Node3D = main.fleet.ships[0]
	var s: Vector3 = flagship.position
	_view(s + Vector3(330, 60, -420), s + Vector3(0, 0, 150), 60.0)
	await _save("07_fleet")
	_view(s + Vector3(60, 25, -230), s + Vector3(0, -5, -60), 60.0)
	await _save("08_flagship_close")
	_view(s + Vector3(-190, -70, 40), s + Vector3(0, 0, -20), 65.0)
	await _save("09_flagship_below")

	# Flying up beside the flagship.
	main.cam.make_current()
	glider.reset(s + Vector3(70, 30, 260), flagship.heading)
	main.cam.snap()
	await _wait(60)
	await _save("10_alongside")

	# Low over the sea of clouds, then high above it all.
	glider.reset(Vector3(900, 150, 400), 0.6)
	main.cam.snap()
	await _wait(90)
	await _save("11_cloud_sea")
	glider.reset(Vector3(0, 1700, 0), 2.4)
	main.cam.snap()
	await _wait(90)
	await _save("12_high")

	# Among the cumulus.
	glider.reset(Vector3(-600, 430, 900), 4.0)
	main.cam.snap()
	await _wait(90)
	await _save("13_cumulus")
	quit()
