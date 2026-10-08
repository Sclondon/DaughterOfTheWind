extends Node3D
## Daughter of the Wind: a white glider, a sky of clouds, giant metal airships, and a windy coast.
##
## The whole world is put together here in code: the painted sky and the sun, the cloud manager,
## the glider with its input and camera, the HUD, and whatever the level adds on top:
##   "clouds"  the sea of clouds, with the airship fleet
##   "coast"   an ocean and a grassy island of cliffs, farms, windmills and rock spires (coast.gd)
## This script also fades the view to white when the camera is inside a cloud, and handles
## restart (R), the weather keys (1 / 2 / 3) and switching level (L, or the button on the HUD).
##
## Tests set the exported switches below before adding the scene to the tree.

const CloudManager := preload("res://scripts/cloud_manager.gd")
const Glider := preload("res://scripts/glider.gd")
const FlightInput := preload("res://scripts/flight_input.gd")
const ChaseCam := preload("res://scripts/chase_cam.gd")
const Fleet := preload("res://scripts/fleet.gd")
const Coast := preload("res://scripts/coast.gd")
const Hud := preload("res://scripts/hud.gd")
const SkyShader := preload("res://shaders/sky.gdshader")

const LEVELS := ["clouds", "coast"]
const LEVEL_NAMES := {"clouds": "Sea of Clouds", "coast": "The Windward Coast"}
const ZENITH := Color(0.09, 0.29, 0.7)
const HAZE := Color(0.73, 0.85, 0.96)
const SUN := Color(1.0, 0.95, 0.82)
const HAZE_DISTANCE := 8500.0

## The level picked last, kept across a scene reload.
static var chosen := "clouds"

## Which level to build. Empty means the one picked last.
@export var level := ""
## False flies an empty sky (no ships), for tests of the flight alone.
@export var use_fleet := true
## False ignores gamepads, so a stuck stick cannot steer a test.
@export var use_pads := true
@export var show_hud := true

## The direction TO the sun.
var sun_dir := Vector3(-0.5, 0.55, -0.67).normalized()

var clouds: Node3D
var glider: Node3D
var input: Node
var cam: Camera3D
var fleet: Node3D
var coast: Node3D
var hud: CanvasLayer
var start := Vector3(0, 620, 0)

var _env: Environment
var _whiteout := 0.0


func _ready() -> void:
	if level == "":
		level = chosen
	_build_sky()

	glider = Glider.new()
	input = FlightInput.new()
	input.use_pads = use_pads
	add_child(input)
	glider.input = input
	add_child(glider)

	clouds = CloudManager.new()
	clouds.sun_dir = sun_dir
	clouds.haze_color = HAZE
	clouds.haze_distance = HAZE_DISTANCE
	clouds.focus = glider
	if level == "coast":
		# Real ground below: no sea of clouds, and the cloud bases lifted clear of the hills.
		clouds.sea_enabled = false
		clouds.altitude_shift = 420.0
		clouds.wind = Vector3(1.5, 0.0, -5.0)
	add_child(clouds)
	glider.air.append(clouds)

	if level == "coast":
		coast = Coast.new()
		coast.focus = glider
		coast.sun_dir = sun_dir
		coast.haze_color = HAZE
		coast.sky_color = ZENITH
		coast.haze_distance = HAZE_DISTANCE
		coast.noise_tex = clouds.noise_texture()
		add_child(coast)
		glider.air.append(coast)
		glider.solids.append(coast)
		start = coast.start_position()
	elif use_fleet:
		fleet = Fleet.new()
		fleet.focus = glider
		add_child(fleet)
		glider.solids.append(fleet)

	cam = ChaseCam.new()
	cam.target = glider
	add_child(cam)
	cam.make_current()

	if show_hud:
		hud = Hud.new()
		hud.glider = glider
		hud.input = input
		hud.level_name = LEVEL_NAMES[level]
		add_child(hud)
		hud.level_pressed.connect(next_level)

	restart()
	clouds.prewarm()
	input.reset_pressed.connect(restart)
	input.weather_pressed.connect(clouds.set_weather)
	input.level_pressed.connect(next_level)


func _build_sky() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SkyShader
	sky_mat.set_shader_parameter("zenith", ZENITH)
	sky_mat.set_shader_parameter("horizon", HAZE)
	sky_mat.set_shader_parameter("sun_color", SUN)
	sky_mat.set_shader_parameter("sun_dir", sun_dir)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL

	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 1.0
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Distance haze on the glider, the ships and the land. The clouds and the ocean do their own.
	_env.fog_enabled = true
	_env.fog_light_color = HAZE
	_env.fog_density = 1.0 / HAZE_DISTANCE
	_env.fog_sky_affect = 0.0
	var world := WorldEnvironment.new()
	world.environment = _env
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.basis = Basis.looking_at(-sun_dir, Vector3.UP)
	sun.light_color = SUN
	sun.light_energy = 1.25
	add_child(sun)


func restart() -> void:
	glider.reset(start)
	if fleet:
		# The convoy starts ahead and a little to one side, sailing nearly the same way.
		fleet.place(start + Vector3(260, -70, -1150), 0.22)
	cam.snap()


## Reload the scene as the next level in LEVELS.
func next_level() -> void:
	chosen = LEVELS[(LEVELS.find(level) + 1) % LEVELS.size()]
	get_tree().reload_current_scene()


func _process(delta: float) -> void:
	# White out as the camera goes into cloud, and thicken the haze around the glider with it.
	var thick: float = clouds.density_at(cam.global_position)
	_whiteout = lerpf(_whiteout, thick, 1.0 - exp(-6.0 * delta))
	_env.fog_density = lerpf(1.0 / HAZE_DISTANCE, 0.02, _whiteout * _whiteout)
	if hud:
		hud.whiteout = _whiteout
