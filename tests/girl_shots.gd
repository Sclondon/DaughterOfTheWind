extends SceneTree
## Close-ups of the girl model standing in her T pose, from all round. Needs a window.
## Run: godot --path . -s res://tests/girl_shots.gd -- <output folder>

const Girl := preload("res://scripts/girl.gd")
const Main := preload("res://scripts/main.gd")
const SkyShader := preload("res://shaders/sky.gdshader")


func _initialize() -> void:
	_run()


func _run() -> void:
	var out_dir: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var world := Node3D.new()
	root.add_child(world)
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SkyShader
	sky_mat.set_shader_parameter("zenith", Main.ZENITH)
	sky_mat.set_shader_parameter("horizon", Main.HAZE)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var holder := WorldEnvironment.new()
	holder.environment = env
	world.add_child(holder)
	var sun := DirectionalLight3D.new()
	sun.basis = Basis.looking_at(Vector3(-0.5, -0.6, -0.6), Vector3.UP)
	world.add_child(sun)
	var girl: Node3D = Girl.new()
	world.add_child(girl)
	var cam := Camera3D.new()
	cam.fov = 40.0
	world.add_child(cam)
	cam.make_current()
	# She faces -Z here. Each view: where the camera is, what it looks at, and a name.
	var views := [
		[Vector3(0.5, 1.0, -2.6), Vector3(0, 0.78, 0), "front"],
		[Vector3(-0.6, 1.1, 2.6), Vector3(0, 0.78, 0), "back"],
		[Vector3(2.6, 1.0, -0.4), Vector3(0, 0.78, 0), "side"],
		[Vector3(0.18, 1.4, -0.75), Vector3(0, 1.36, 0), "face"],
		[Vector3(0.5, 1.42, -0.6), Vector3(0, 1.35, 0), "face_side"],
		[Vector3(-0.72, 1.5, -0.45), Vector3(-0.66, 1.2, 0), "hand"],
		[Vector3(-0.95, 1.0, -0.25), Vector3(-0.68, 1.17, 0), "fist"],
		[Vector3(0.0, 1.45, 0.75), Vector3(0, 1.38, 0), "hair_back"],
		[Vector3(0.1, 2.1, -0.1), Vector3(0, 1.4, 0), "hair_top"],
		[Vector3(0.5, 0.5, -1.0), Vector3(0, 0.72, 0), "hips"],
		[Vector3(0.3, 0.95, -0.9), Vector3(0, 0.82, 0), "belt"],
		[Vector3(0.4, 0.3, -0.8), Vector3(0, 0.18, 0), "boots"],
	]
	for view: Array in views:
		cam.global_transform = Transform3D(Basis.looking_at((view[1] as Vector3) - (view[0] as Vector3), Vector3.UP), view[0])
		for f in 6:
			await process_frame
		root.get_texture().get_image().save_png(out_dir.path_join("girl_%s.png" % view[2]))
	quit()
