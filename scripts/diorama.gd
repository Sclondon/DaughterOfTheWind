extends Node3D
## The diorama: a small test room for looking at the cel shading. The glider (or the witch) hangs
## in a steady wind over a little turntable, with a few plain shapes beside it and small clouds
## drifting past. Nothing here can hurt you and nothing is flown: it is for looking.
##
## The camera goes all the way round: drag to turn it (any direction, over the top and
## underneath), wheel or pinch to zoom. The flying keys still work the flaps and lean the glider,
## so the moving parts can be seen. The sun can be walked round the sky to watch the shading
## change: Z / X, or the buttons.
##
## Reached from the game with L (it is the third "level"); L or the button goes back.

const Main := preload("res://scripts/main.gd")
const Glider := preload("res://scripts/glider.gd")
const FlightInput := preload("res://scripts/flight_input.gd")
const CloudManager := preload("res://scripts/cloud_manager.gd")
const SunGlare := preload("res://scripts/sun_glare.gd")
const Toon := preload("res://scripts/toon.gd")
const PuffShader := preload("res://shaders/cloud_puff.gdshader")
const SkyShader := preload("res://shaders/sky.gdshader")

## The wind the glider hangs in (it blows from her nose to her tail), and how fast the clouds drift.
const WIND := Vector3(0, 0, 30.0)
const CLOUD_DRIFT := Vector3(1.5, 0.0, 7.0)
## The clouds live in a box this big round the turntable and come back in at the far side.
const CLOUD_BOX := Vector3(420.0, 120.0, 420.0)
const SUN_HEIGHT := 0.6

var glider: Node3D
var input: Node
var cam: Camera3D

## Where the camera is: turned round (yaw), tipped up or down (pitch), and how far out.
var yaw := 0.6
var pitch := 0.25
var distance := 11.0
## How far round the sky the sun is (radians).
var sun_turn := 2.5

var _sun: DirectionalLight3D
var _sky_mat: ShaderMaterial
var _puff_mat: ShaderMaterial
var _glare: ColorRect
var _clouds := MultiMesh.new()
var _cloud_at: Array = []  # each puff's place, before the drift
var _cloud_basis: Array = []
var _time := 0.0
var _touches := {}
var _pinch := 0.0


func _ready() -> void:
	_build_sky()
	_build_stage()
	_build_clouds()

	input = FlightInput.new()
	# Touches turn the camera here, so the flying stick is keys and gamepad only.
	input.touch_enabled = false
	add_child(input)
	glider = Glider.new()
	glider.rider = Main.chosen_rider
	glider.input = input
	add_child(glider)
	# She is held in place, not flown.
	glider.set_physics_process(false)
	for hair: Node in get_tree().get_nodes_in_group("hair"):
		hair.wind = WIND

	cam = Camera3D.new()
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cam.fov = 55.0
	cam.near = 0.2
	cam.far = 4000.0
	add_child(cam)
	cam.make_current()

	var lens := CanvasLayer.new()
	add_child(lens)
	_glare = SunGlare.new()
	_glare.camera = cam
	lens.add_child(_glare)
	_build_buttons()
	_place_sun()
	input.level_pressed.connect(_back)
	input.rider_pressed.connect(_swap_rider)


func _build_sky() -> void:
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = SkyShader
	_sky_mat.set_shader_parameter("zenith", Main.ZENITH)
	_sky_mat.set_shader_parameter("horizon", Main.HAZE)
	_sky_mat.set_shader_parameter("sun_color", Main.SUN)
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	_sun = DirectionalLight3D.new()
	_sun.light_color = Main.SUN
	_sun.light_energy = 1.25
	add_child(_sun)


## The turntable, and a few plain shapes on stands: a ball, a block, a cone and a ring, each one
## flat colour, to show what the shading does to simple forms.
func _build_stage() -> void:
	var table := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 7.0
	disc.bottom_radius = 7.4
	disc.height = 0.5
	disc.radial_segments = 48
	table.mesh = disc
	table.material_override = Toon.paint(Color(0.86, 0.8, 0.68))
	table.position.y = -3.7
	add_child(table)

	var ball := SphereMesh.new()
	ball.radius = 0.8
	ball.height = 1.6
	var block := BoxMesh.new()
	block.size = Vector3(1.3, 1.3, 1.3)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.8
	cone.height = 1.6
	var ring := TorusMesh.new()
	ring.inner_radius = 0.45
	ring.outer_radius = 0.9
	var shapes := [
		[ball, Color(0.9, 0.3, 0.25)], [block, Color(0.25, 0.5, 0.85)],
		[cone, Color(0.95, 0.8, 0.3)], [ring, Color(0.35, 0.65, 0.35)],
	]
	for i in shapes.size():
		var around: float = TAU * (float(i) + 0.5) / float(shapes.size())
		var at := Vector3(cos(around) * 5.2, -3.45, sin(around) * 5.2)
		var stand := MeshInstance3D.new()
		var post := CylinderMesh.new()
		post.top_radius = 0.5
		post.bottom_radius = 0.6
		post.height = 0.9
		stand.mesh = post
		stand.material_override = Toon.paint(Color(0.7, 0.66, 0.6))
		stand.position = at + Vector3(0, 0.45, 0)
		add_child(stand)
		var shape := MeshInstance3D.new()
		shape.mesh = shapes[i][0]
		shape.material_override = Toon.paint(shapes[i][1])
		shape.position = at + Vector3(0, 1.9, 0)
		add_child(shape)


## A handful of small clouds, drawn with the game's own cloud shader.
func _build_clouds() -> void:
	var maker: Node3D = CloudManager.new()
	var noise: ImageTexture = maker._make_noise()
	maker.free()
	_puff_mat = ShaderMaterial.new()
	_puff_mat.shader = PuffShader
	_puff_mat.set_shader_parameter("noise_tex", noise)
	_puff_mat.set_shader_parameter("haze_color", Main.HAZE)
	_puff_mat.set_shader_parameter("haze_distance", 3000.0)
	_puff_mat.set_shader_parameter("fade_start", 5000.0)
	_puff_mat.set_shader_parameter("fade_end", 6000.0)

	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var customs: Array = []
	var colors: Array = []
	for c in 22:
		# Keep the middle clear, so no cloud sits on the turntable.
		var heart := Vector3(rng.randf_range(-0.5, 0.5) * CLOUD_BOX.x, rng.randf_range(-0.35, 0.5) * CLOUD_BOX.y,
				rng.randf_range(-0.5, 0.5) * CLOUD_BOX.z)
		if absf(heart.x) < 26.0:
			heart.x = 26.0 * (1.0 if heart.x >= 0.0 else -1.0) + heart.x
		var size: float = rng.randf_range(5.0, 12.0)
		for p in rng.randi_range(6, 11):
			var out := Vector3(rng.randf_range(-1.6, 1.6), rng.randf_range(0.0, 0.9), rng.randf_range(-1.0, 1.0)) * size
			var r: float = size * rng.randf_range(0.55, 1.0) * (1.0 - out.y / (size * 2.0))
			_cloud_at.append(heart + out)
			_cloud_basis.append(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * r))
			# A flat bottom at the cloud's base, and how high in the cloud this puff is.
			customs.append(Color(rng.randf(), clampf(-out.y / r - 0.3, -2.0, 1.0), clampf(out.y / size, 0.0, 1.0), 0.0))
			var from_core: Vector3 = (out + Vector3(0, size * 0.3, 0)).normalized()
			colors.append(Color(from_core.x * 0.5 + 0.5, from_core.y * 0.5 + 0.5, from_core.z * 0.5 + 0.5))
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 28
	sphere.rings = 14
	_clouds.transform_format = MultiMesh.TRANSFORM_3D
	_clouds.use_colors = true
	_clouds.use_custom_data = true
	_clouds.mesh = sphere
	_clouds.instance_count = _cloud_at.size()
	for i in _cloud_at.size():
		_clouds.set_instance_color(i, colors[i])
		_clouds.set_instance_custom_data(i, customs[i])
	var node := MultiMeshInstance3D.new()
	node.multimesh = _clouds
	node.material_override = _puff_mat
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	node.custom_aabb = AABB(-CLOUD_BOX, CLOUD_BOX * 2.0)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


func _build_buttons() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(1, 1, 1, 0.18)
	plate.set_corner_radius_all(14)
	plate.set_content_margin_all(8)
	plate.content_margin_left = 14
	plate.content_margin_right = 14
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.anchor_left = 1.0
	column.anchor_right = 1.0
	column.offset_left = -236.0
	column.offset_right = -16.0
	column.offset_top = 16.0
	layer.add_child(column)
	var rider_name: String = Main.RIDER_NAMES[Main.chosen_rider]
	for spec: Array in [["Back to flying  ›", _back], ["%s  ›" % rider_name, _swap_rider],
			["Sun round  ↻", func() -> void: _turn_sun(PI / 6.0)]]:
		var button := Button.new()
		button.text = spec[0]
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 16)
		for state: String in ["normal", "hover", "pressed"]:
			button.add_theme_stylebox_override(state, plate)
		button.pressed.connect(spec[1])
		column.add_child(button)

	var help := Label.new()
	help.text = "Drag to turn the camera  ·  wheel or pinch to zoom  ·  A D W S work the flaps  ·  Z X move the sun"
	help.add_theme_font_size_override("font_size", 16)
	help.add_theme_color_override("font_outline_color", Color(0.15, 0.25, 0.45, 0.6))
	help.add_theme_constant_override("outline_size", 5)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help.anchor_right = 1.0
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.offset_top = -44.0
	help.offset_bottom = -16.0
	layer.add_child(help)


func _back() -> void:
	Main.chosen = Main.LEVELS[0]
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _swap_rider() -> void:
	Main.chosen_rider = "glider" if Main.chosen_rider == "witch" else "witch"
	get_tree().reload_current_scene()


func _turn_sun(by: float) -> void:
	sun_turn = wrapf(sun_turn + by, 0.0, TAU)
	_place_sun()


## Point the light, the sky's sun, the clouds' shading and the glare all the same way.
func _place_sun() -> void:
	var to_sun := Vector3(cos(sun_turn) * cos(SUN_HEIGHT), sin(SUN_HEIGHT), sin(sun_turn) * cos(SUN_HEIGHT))
	_sun.basis = Basis.looking_at(-to_sun, Vector3.UP)
	_sky_mat.set_shader_parameter("sun_dir", to_sun)
	_puff_mat.set_shader_parameter("sun_dir", to_sun)
	_glare.sun_dir = to_sun


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		_pinch = 0.0
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			# Two fingers: pinch to zoom.
			var points: Array = _touches.values()
			var apart: float = (points[0] as Vector2).distance_to(points[1])
			if _pinch > 0.0:
				distance = clampf(distance * _pinch / maxf(apart, 1.0), 2.5, 120.0)
			_pinch = apart
		else:
			# One finger (or the mouse): turn the camera. It goes right over the top and
			# underneath; it only stops just short of straight up and straight down.
			yaw -= event.relative.x * 0.008
			pitch = clampf(pitch + event.relative.y * 0.008, -1.55, 1.55)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = clampf(distance * 0.9, 2.5, 120.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = clampf(distance / 0.9, 2.5, 120.0)


func _process(delta: float) -> void:
	_time += delta
	if Input.is_physical_key_pressed(KEY_Z):
		_turn_sun(-delta * 0.9)
	if Input.is_physical_key_pressed(KEY_X):
		_turn_sun(delta * 0.9)

	# The glider hangs in the wind: bobbing a little, leaning with the stick, flaps working.
	var stick: Vector2 = input.stick
	glider.control = glider.control.lerp(stick, 1.0 - exp(-7.0 * delta))
	glider.boosting = input.boost
	glider.airspeed = WIND.length()
	# Pulling up counts as climbing and pushing down as falling, so her poses can be seen.
	glider.climb = glider.control.y * 16.0
	glider.load_factor = 1.0 + absf(glider.control.x) * 0.8 + maxf(glider.control.y, 0.0) * 1.2
	glider.position = Vector3(0, sin(_time * 0.9) * 0.18, 0)
	glider.basis = Basis(Vector3.BACK, -glider.control.x * 0.7) * Basis(Vector3.RIGHT, glider.control.y * 0.3)

	var out := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var eye: Vector3 = out * distance + Vector3(0, 0.3, 0)
	cam.global_transform = Transform3D(Basis.looking_at(-out, Vector3.UP), eye)

	# The clouds drift through their box and come back in on the other side.
	var drift: Vector3 = CLOUD_DRIFT * _time
	for i in _cloud_at.size():
		var at: Vector3 = (_cloud_at[i] as Vector3) + drift
		at.x = wrapf(at.x, -CLOUD_BOX.x * 0.5, CLOUD_BOX.x * 0.5)
		at.z = wrapf(at.z, -CLOUD_BOX.z * 0.5, CLOUD_BOX.z * 0.5)
		_clouds.set_instance_transform(i, Transform3D(_cloud_basis[i], at))
