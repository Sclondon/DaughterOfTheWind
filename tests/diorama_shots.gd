extends SceneTree
## Screenshots of the diorama from a few sides, then of the girl standing, crouched and hanging.
## Needs a window (no --headless).
## Run: godot --fixed-fps 60 --path . -s res://tests/diorama_shots.gd -- <output folder>

const Diorama := preload("res://scenes/diorama.tscn")


func _initialize() -> void:
	_run()


func _run() -> void:
	var out_dir: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var room: Node3D = Diorama.instantiate()
	root.add_child(room)
	await process_frame
	room.input.manual = true
	# Each view: camera yaw, pitch, distance, where the sun is, the stick, and a name.
	var views := [
		[0.6, 0.25, 11.0, 2.5, Vector2.ZERO, "three_quarter"],
		[2.6, 0.5, 9.0, 2.5, Vector2.ZERO, "from_behind"],
		[4.2, -0.5, 10.0, 0.4, Vector2.ZERO, "from_below"],
		[0.0, 1.5, 12.0, 4.4, Vector2.ZERO, "from_above"],
		[1.57, 0.08, 4.2, 2.2, Vector2.ZERO, "stand_side"],
		[0.5, 0.2, 4.0, 2.5, Vector2.ZERO, "stand_front"],
		[2.5, 0.25, 4.0, 2.5, Vector2.ZERO, "stand_back"],
		[1.57, 0.08, 4.2, 2.2, Vector2(0, 1), "crouch_side"],
		[1.57, 0.08, 4.2, 2.2, Vector2(0, -1), "dangle_side"],
		[2.4, 0.3, 6.5, 2.5, Vector2(1, 0), "roll_right"],
		# Close on her: hands on the hoops, hair, scarf, skirt, and each pose.
		[1.57, 0.15, 2.0, 2.2, Vector2.ZERO, "close_side"],
		[0.45, 0.3, 1.9, 2.5, Vector2.ZERO, "close_front"],
		[2.7, 0.35, 2.0, 2.5, Vector2.ZERO, "close_back"],
		[4.4, 0.25, 2.0, 0.6, Vector2.ZERO, "close_other_side"],
		[0.0, 0.9, 1.7, 2.5, Vector2.ZERO, "close_hands"],
		[1.57, 0.15, 2.0, 2.2, Vector2(0, 0.6), "close_easy_pull"],
		[1.57, 0.15, 2.0, 2.2, Vector2(0, 1), "close_crouch"],
		[2.2, 0.25, 2.2, 2.5, Vector2(0, -1), "close_dangle"],
	]
	for i in views.size():
		room.yaw = views[i][0]
		room.pitch = views[i][1]
		room.distance = views[i][2]
		room.sun_turn = views[i][3]
		room.input.stick = views[i][4]
		room._place_sun()
		for f in 90:
			await process_frame
		root.get_texture().get_image().save_png(out_dir.path_join("%02d_%s.png" % [i, views[i][5]]))
	quit()
